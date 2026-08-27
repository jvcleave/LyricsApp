import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let viewModel: LyricsFinderViewModel

    @State private var isShowingImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            HStack {
                Button {
                    isShowingImporter = true
                } label: {
                    Label(
                        viewModel.hasImportedFile ? "Import Another File" : "Import MP3",
                        systemImage: "music.note"
                    )
                }
                .keyboardShortcut("o", modifiers: .command)

                if case .importing = viewModel.phase {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading audio metadata…")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let fileName = viewModel.fileName {
                MetadataEditorView(fileName: fileName, viewModel: viewModel)
                Divider()
            }

            phaseContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 560)
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    viewModel.importAudioFile(at: url)
                }
            case let .failure(error):
                viewModel.presentImportError(error)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lyrics Finder")
                .font(.largeTitle.weight(.semibold))
            Text("Import an audio file, check its metadata, then search LRCLIB.")
                .foregroundStyle(.secondary)
            Text("Your audio stays on this Mac. Only track metadata is sent when you search.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {
        case .idle:
            ContentUnavailableView(
                "Import an MP3",
                systemImage: "music.note.list",
                description: Text("Choose an audio file to read its track information.")
            )
        case .importing, .ready:
            if viewModel.hasImportedFile {
                ContentUnavailableView(
                    "Ready to Search",
                    systemImage: "text.magnifyingglass",
                    description: Text("Review the metadata above and select Find Lyrics.")
                )
            }
        case .searching:
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching LRCLIB…")
                    .font(.headline)
                Text("Trying an exact lookup before a broader search.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .candidates(items):
            SearchResultsView(items: items) { id in
                viewModel.selectCandidate(id: id)
            }
        case let .found(content):
            LyricsView(content: content)
        case .notFound:
            ContentUnavailableView(
                "No Lyrics Found",
                systemImage: "text.magnifyingglass",
                description: Text("Try correcting the title or artist, then search again.")
            )
        case let .failed(message):
            ContentUnavailableView(
                "Something Went Wrong",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }
}

#Preview {
    ContentView(viewModel: LyricsFinderViewModel())
}
