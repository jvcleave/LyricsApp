import Foundation

public struct LyricsMatchRanker: Sendable {
    public init() {}

    public func ranked(
        results: [LyricsResult],
        input: LyricsMatchInput
    ) -> [RankedLyricsCandidate] {
        results
            .map { result in rank(result: result, input: input) }
            .sorted {
                if $0.score == $1.score {
                    return ($0.durationDifference ?? .greatestFiniteMagnitude)
                        < ($1.durationDifference ?? .greatestFiniteMagnitude)
                }
                return $0.score > $1.score
            }
    }

    public func shouldSelectAutomatically(
        best: RankedLyricsCandidate,
        runnerUp: RankedLyricsCandidate?,
        input: LyricsMatchInput
    ) -> Bool {
        let artistRequirementMet = normalized(input.artist).isEmpty || best.exactArtist
        let durationRequirementMet = best.durationDifference.map { $0 <= 5 } ?? true

        if best.exactTitle && artistRequirementMet && durationRequirementMet {
            return true
        }

        let lead = best.score - (runnerUp?.score ?? 0)
        return best.score >= 180 && lead >= 35
    }

    private func rank(
        result: LyricsResult,
        input: LyricsMatchInput
    ) -> RankedLyricsCandidate {
        let inputTitle = normalized(input.title)
        let resultTitle = normalized(result.trackName)
        let inputArtist = normalized(input.artist)
        let resultArtist = normalized(result.artistName)
        let inputAlbum = normalized(input.album)
        let resultAlbum = normalized(result.albumName ?? "")

        let exactTitle = inputTitle.isEmpty == false && inputTitle == resultTitle
        let exactArtist = inputArtist.isEmpty == false && inputArtist == resultArtist
        var score = 0

        if exactTitle {
            score += 140
        } else if containsEither(first: inputTitle, second: resultTitle) {
            score += 55
        }

        if exactArtist {
            score += 160
        } else if containsEither(first: inputArtist, second: resultArtist) {
            score += 45
        }

        if inputAlbum.isEmpty == false && inputAlbum == resultAlbum {
            score += 35
        }

        let durationDifference: TimeInterval?
        if let inputDuration = input.duration, let resultDuration = result.duration {
            let difference = abs(inputDuration - resultDuration)
            durationDifference = difference
            switch difference {
                case ...2:
                    score += 40
                case ...5:
                    score += 30
                case ...10:
                    score += 20
                case ...20:
                    score += 10
                default:
                    break
            }
        } else {
            durationDifference = nil
        }

        return RankedLyricsCandidate(
            result: result,
            score: score,
            durationDifference: durationDifference,
            exactTitle: exactTitle,
            exactArtist: exactArtist
        )
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private func containsEither(
        first: String,
        second: String
    ) -> Bool {
        if first.isEmpty || second.isEmpty {
            return false
        }
        return first.contains(second) || second.contains(first)
    }
}
