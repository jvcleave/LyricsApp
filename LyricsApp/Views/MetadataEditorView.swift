import SwiftUI

struct MetadataEditorView: View {
    let fileName: String
    let viewModel: LyricsFinderViewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 14) {
            Label(fileName, systemImage: "doc.fill")
                .font(.headline)
                .lineLimit(1)
                .help(fileName)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Title")
                    TextField("Track title", text: $viewModel.title)
                }
                GridRow {
                    Text("Artist")
                    TextField("Artist", text: $viewModel.artist)
                }
                GridRow {
                    Text("Album")
                    TextField("Album (optional)", text: $viewModel.album)
                }
                GridRow {
                    Text("Duration")
                    HStack(spacing: 8) {
                        TextField("Seconds", text: $viewModel.durationText)
                            .frame(maxWidth: 140)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(viewModel.isBusy)

            Button("Find Lyrics") {
                viewModel.findLyrics()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canFindLyrics)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}
