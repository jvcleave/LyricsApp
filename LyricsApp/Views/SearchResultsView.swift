import SwiftUI

struct SearchResultsView: View {
    let items: [LyricsCandidateDisplayItem]
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a Match")
                .font(.title2.weight(.semibold))
            Text("Several LRCLIB results could match this file.")
                .foregroundStyle(.secondary)

            List(items) { item in
                Button {
                    onSelect(item.id)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.artist)
                                .foregroundStyle(.secondary)
                            if let album = item.album {
                                Text(album)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(item.durationText)
                                .monospacedDigit()
                            if let matchDetail = item.matchDetail {
                                Text(matchDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }
}
