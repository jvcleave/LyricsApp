import Foundation

struct LyricsLookupFallbackBuilder: Sendable {
    static let maximumAttemptCount = 5

    init() {}

    func inputs(startingWith input: LyricsMatchInput) -> [LyricsMatchInput] {
        var inputs = [input]
        let cleanedArtist = removingWrappedGroups(from: input.artist)
        let cleanedAlbum = removingWrappedGroups(from: input.album)
        appendIfUseful(
            LyricsMatchInput(
                title: removingWrappedGroups(from: input.title),
                artist: cleanedArtist,
                album: cleanedAlbum,
                duration: input.duration
            ),
            to: &inputs
        )

        var currentTitle = input.title.trimmingCharacters(in: .whitespacesAndNewlines)

        while inputs.count < Self.maximumAttemptCount {
            let characters = Array(currentTitle)
            guard let closingCharacter = characters.last else { break }

            let openingCharacter: Character
            switch closingCharacter {
                case ")":
                    openingCharacter = "("
                case "]":
                    openingCharacter = "["
                case "}":
                    openingCharacter = "{"
                default:
                    return inputs
            }

            var depth = 0
            var openingIndex: Int?
            for index in characters.indices.reversed() {
                let character = characters[index]
                if character == closingCharacter {
                    depth += 1
                } else if character == openingCharacter {
                    depth -= 1
                    if depth == 0 {
                        openingIndex = index
                        break
                    }
                }
            }

            guard let openingIndex else { break }
            let strippedTitle = String(characters[..<openingIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if strippedTitle.isEmpty || strippedTitle == currentTitle {
                break
            }

            appendIfUseful(
                LyricsMatchInput(
                    title: strippedTitle,
                    artist: cleanedArtist,
                    album: cleanedAlbum,
                    duration: input.duration
                ),
                to: &inputs
            )
            currentTitle = strippedTitle
        }

        return inputs
    }

    private func appendIfUseful(
        _ input: LyricsMatchInput,
        to inputs: inout [LyricsMatchInput]
    ) {
        if input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        let isDuplicate = inputs.contains {
            $0.title == input.title
                && $0.artist == input.artist
                && $0.album == input.album
        }
        if isDuplicate == false, inputs.count < Self.maximumAttemptCount {
            inputs.append(input)
        }
    }

    private func removingWrappedGroups(from value: String) -> String {
        let characters = Array(value)
        var openingCharacters: [(character: Character, index: Int)] = []
        var rangesToRemove: [ClosedRange<Int>] = []

        for (index, character) in characters.enumerated() {
            if "([{".contains(character) {
                openingCharacters.append((character, index))
                continue
            }

            let expectedOpeningCharacter: Character?
            switch character {
                case ")": expectedOpeningCharacter = "("
                case "]": expectedOpeningCharacter = "["
                case "}": expectedOpeningCharacter = "{"
                default: expectedOpeningCharacter = nil
            }
            guard let expectedOpeningCharacter,
                  openingCharacters.last?.character == expectedOpeningCharacter else {
                continue
            }

            let opening = openingCharacters.removeLast()
            if openingCharacters.isEmpty {
                rangesToRemove.append(opening.index ... index)
            }
        }

        let cleaned = characters.enumerated().compactMap { index, character in
            rangesToRemove.contains { $0.contains(index) } ? nil : character
        }
        return String(cleaned)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
