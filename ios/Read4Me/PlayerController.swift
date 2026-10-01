import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class PlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var bookID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var speed: Float = 1
    @Published private(set) var sleepDeadline: Date?
    private let library: LibraryStore
    private var audio: AVAudioPlayer?
    private var chunkIndex = 0
    private var timer: Timer?
    private var lastSaved: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []

    init(library: LibraryStore) {
        self.library = library
        super.init()
        configureRemoteCommands()
        if let id = library.lastPlayedID { load(id) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.pause() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.pause() }
        })
    }

    deinit {
        timer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for (command, target) in remoteTargets { command.removeTarget(target) }
    }

    var currentBook: Book? {
        guard let bookID else { return nil }
        return library.book(bookID)
    }

    func load(_ id: UUID) {
        guard let book = library.book(id), book.isReady else { return }
        pause()
        bookID = id
        speed = book.speed
        position = book.position
        do {
            try prepare(at: position)
            try library.rememberPlayback(id)
            updateNowPlaying()
        }
        catch { library.error = error.localizedDescription }
    }

    func play() {
        guard let book = currentBook else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            if position >= book.duration { try prepare(at: 0) }
            guard let audio else { return }
            audio.rate = speed
            isPlaying = audio.play()
            updateNowPlaying()
        } catch { library.error = error.localizedDescription }
    }

    func pause() {
        audio?.pause()
        isPlaying = false
        syncPosition()
        persist()
        updateNowPlaying()
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(_ value: TimeInterval) {
        let resume = isPlaying
        do {
            try prepare(at: value)
            persist()
            if resume { play() }
            updateNowPlaying()
        } catch { library.error = error.localizedDescription }
    }

    func skip(_ seconds: TimeInterval) { seek(position + seconds) }
    func setSpeed(_ value: Float) {
        speed = value
        audio?.rate = value
        persist()
        updateNowPlaying()
    }
    func setSleepTimer(minutes: Int) {
        sleepDeadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }
    func cancelSleepTimer() { sleepDeadline = nil }
    func clear() {
        pause()
        audio = nil
        bookID = nil
        position = 0
        sleepDeadline = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func prepare(at value: TimeInterval) throws {
        guard let book = currentBook else { return }
        let target = min(max(0, value), book.duration)
        var offset: TimeInterval = 0
        for index in book.chunks.indices {
            let end = offset + book.chunks[index].duration
            if target < end || index == book.chunks.count - 1 {
                let next = try AVAudioPlayer(contentsOf: library.audioURL(for: book.id, chunk: index))
                audio?.stop()
                audio = next
                chunkIndex = index
                next.delegate = self
                next.enableRate = true
                next.rate = speed
                next.currentTime = target - offset
                next.prepareToPlay()
                position = target
                isPlaying = false
                return
            }
            offset = end
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard let book = currentBook else { return }
            if !flag { pause(); return }
            let next = chunkIndex + 1
            if next < book.chunks.count {
                let offset = book.chunks.prefix(next).reduce(0) { $0 + $1.duration }
                do { try prepare(at: offset); play() }
                catch { library.error = error.localizedDescription; pause() }
            } else {
                position = book.duration
                isPlaying = false
                persist()
                updateNowPlaying()
            }
        }
    }

    private func tick() {
        if let sleepDeadline, Date() >= sleepDeadline {
            self.sleepDeadline = nil
            pause()
        }
        guard isPlaying else { return }
        syncPosition()
        if abs(position - lastSaved) >= 5 { persist() }
        updateNowPlaying()
    }
    private func syncPosition() {
        guard let book = currentBook, let audio else { return }
        position = book.chunks.prefix(chunkIndex).reduce(0) { $0 + $1.duration } + audio.currentTime
    }
    func persist() {
        guard var book = currentBook else { return }
        book.position = position
        book.speed = speed
        do { try library.update(book); lastSaved = position }
        catch { library.error = "Could not save playback position: \(error.localizedDescription)" }
    }
    private func updateNowPlaying() {
        guard let book = currentBook else { return }
        var rate: Float = 0
        if isPlaying { rate = speed }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: book.title,
            MPMediaItemPropertyArtist: "Read4Me",
            MPMediaItemPropertyPlaybackDuration: book.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: rate
        ]
    }
    private func register(_ command: MPRemoteCommand,
                          action: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        remoteTargets.append((command, command.addTarget(handler: action)))
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        register(commands.playCommand) { [weak self] _ in
            Task { @MainActor in self?.play() }; return .success
        }
        register(commands.pauseCommand) { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }
        register(commands.togglePlayPauseCommand) { [weak self] _ in
            Task { @MainActor in self?.toggle() }; return .success
        }
        commands.skipForwardCommand.preferredIntervals = [30]
        commands.skipBackwardCommand.preferredIntervals = [15]
        register(commands.skipForwardCommand) { [weak self] _ in
            Task { @MainActor in self?.skip(30) }; return .success
        }
        register(commands.skipBackwardCommand) { [weak self] _ in
            Task { @MainActor in self?.skip(-15) }; return .success
        }
        register(commands.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
    }
}
