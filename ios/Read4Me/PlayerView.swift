import SwiftUI

struct PlayerView: View {
    let id: UUID
    @ObservedObject var player: PlayerController

    var body: some View {
        VStack(spacing: 24) {
            if player.bookID == id, let book = player.currentBook {
                Slider(value: Binding(get: { player.position }, set: player.seek),
                       in: 0...max(1, book.duration))
                    .accessibilityLabel("Playback position")
                HStack {
                    Text(Duration.seconds(player.position))
                    Spacer()
                    Text(Duration.seconds(book.duration))
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                HStack(spacing: 40) {
                    Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }
                        .accessibilityLabel("Back 15 seconds")
                    Button(action: player.toggle) {
                        if player.isPlaying { Image(systemName: "pause.circle.fill") }
                        else { Image(systemName: "play.circle.fill") }
                    }.font(.system(size: 64)).accessibilityLabel("Play or pause")
                    Button { player.skip(30) } label: { Image(systemName: "goforward.30") }
                        .accessibilityLabel("Forward 30 seconds")
                }.font(.title)
                HStack {
                    Menu {
                        ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in
                            Button("\(speed.formatted())×") { player.setSpeed(Float(speed)) }
                        }
                    } label: { Label("\(player.speed.formatted())×", systemImage: "speedometer") }
                    Spacer()
                    Menu {
                        ForEach([15, 30, 45, 60], id: \.self) { minutes in
                            Button("\(minutes) minutes") { player.setSleepTimer(minutes: minutes) }
                        }
                        Button("Cancel timer") { player.cancelSleepTimer() }
                    } label: { Label("Sleep timer", systemImage: "moon") }
                }
                if let deadline = player.sleepDeadline {
                    Text("Stops at \(deadline.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button("Open player") { player.load(id) }.buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            if player.bookID != id { player.load(id) }
        }
    }
}
