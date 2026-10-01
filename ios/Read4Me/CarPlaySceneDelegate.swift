import CarPlay
import Combine

// Activate the CarPlay scene configuration only after Apple approves the audio entitlement.
@MainActor
final class CarPlaySceneDelegate: UIResponder, @preconcurrency CPTemplateApplicationSceneDelegate {
    private var controller: CPInterfaceController?
    private var libraryObservation: AnyCancellable?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        controller = interfaceController
        libraryObservation = AppModel.shared.library.$books
            .map { $0.filter(\.isReady) }
            .removeDuplicates(by: { $0.map(\.id) == $1.map(\.id) })
            .sink { [weak self] books in
            self?.showLibrary(books)
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        libraryObservation = nil
        controller = nil
    }

    private func showLibrary(_ books: [Book]) {
        let items = books.filter(\.isReady).map { book in
            let item = CPListItem(text: book.title, detailText: "Resume audiobook")
            item.handler = { [weak self] _, completion in
                let player = AppModel.shared.player
                player.load(book.id)
                player.play()
                self?.controller?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                completion()
            }
            return item
        }
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Read4Me", sections: [section])
        template.emptyViewTitleVariants = ["No audiobooks yet"]
        template.emptyViewSubtitleVariants = ["Create an audiobook on your iPhone first."]
        controller?.setRootTemplate(template, animated: false, completion: nil)
    }
}
