import Foundation

struct LyricsLookupFallbackBuilder: Sendable {
    static let maximumAttemptCount = 5

    init() {}

    func inputs(startingWith input: LyricsMatchInput) -> [LyricsMatchInput] {
        var inputs = [input]
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

            inputs.append(
                LyricsMatchInput(
                    title: strippedTitle,
                    artist: input.artist,
                    album: input.album,
                    duration: input.duration
                )
            )
            currentTitle = strippedTitle
        }

        return inputs
    }
}
