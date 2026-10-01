import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()
    let library = LibraryStore.deviceLibrary()
    let converter: ConversionController
    let player: PlayerController

    private init() {
        converter = ConversionController(library: library)
        player = PlayerController(library: library)
    }
}

@main
struct Read4MeApp: App {
    private let model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView(library: model.library, converter: model.converter, player: model.player)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.converter.requestPause()
                model.player.persist()
            }
        }
    }
}
