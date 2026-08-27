import SwiftUI

struct LyricsView: View {
    let content: LyricsDisplayContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .font(.title2.weight(.semibold))
                Text(content.artist)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let album = content.album {
                    Text(album)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollView {
                lyricsBody
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.trailing, 8)
            }
        }
    }

    @ViewBuilder
    private var lyricsBody: some View {
        switch content.body {
        case .instrumental:
            Label(
                "This track is marked as instrumental.",
                systemImage: "waveform"
            )
            .font(.headline)
            .padding(.vertical)
        case let .timed(lines):
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(timestamp(line.time))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                        Text(line.text.isEmpty ? " " : line.text)
                    }
                }
            }
        case let .plain(lyrics):
            Text(lyrics)
                .font(.body)
                .lineSpacing(5)
        case .unavailable:
            ContentUnavailableView(
                "Lyrics Unavailable",
                systemImage: "text.badge.xmark",
                description: Text("LRCLIB returned this track without readable lyrics.")
            )
        }
    }

    private func timestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
