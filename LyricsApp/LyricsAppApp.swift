import SwiftUI

@main
struct LyricsAppApp: App {
    @State private var viewModel: LyricsFinderViewModel

    init() {
        _viewModel = State(initialValue: LyricsFinderViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 760, height: 720)
    }
}
