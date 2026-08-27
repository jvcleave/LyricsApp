import Foundation

struct LyricsMatchInput: Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval?
}

struct RankedLyricsCandidate: Sendable {
    let result: LyricsResult
    let score: Int
    let durationDifference: TimeInterval?
    let exactTitle: Bool
    let exactArtist: Bool
}

struct LyricsMatchRanker: Sendable {
    func ranked(
        _ results: [LyricsResult],
        for input: LyricsMatchInput
    ) -> [RankedLyricsCandidate] {
        results
            .map { result in rank(result, for: input) }
            .sorted {
                if $0.score == $1.score {
                    return ($0.durationDifference ?? .greatestFiniteMagnitude)
                        < ($1.durationDifference ?? .greatestFiniteMagnitude)
                }
                return $0.score > $1.score
            }
    }

    func shouldSelectAutomatically(
        _ best: RankedLyricsCandidate,
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
        _ result: LyricsResult,
        for input: LyricsMatchInput
    ) -> RankedLyricsCandidate {
        let inputTitle = normalized(input.title)
        let resultTitle = normalized(result.trackName)
        let inputArtist = normalized(input.artist)
        let resultArtist = normalized(result.artistName)
        let inputAlbum = normalized(input.album)
        let resultAlbum = normalized(result.albumName ?? "")

        let exactTitle = !inputTitle.isEmpty && inputTitle == resultTitle
        let exactArtist = !inputArtist.isEmpty && inputArtist == resultArtist
        var score = 0

        if exactTitle {
            score += 140
        } else if containsEither(inputTitle, resultTitle) {
            score += 55
        }

        if exactArtist {
            score += 160
        } else if containsEither(inputArtist, resultArtist) {
            score += 45
        }

        if !inputAlbum.isEmpty && inputAlbum == resultAlbum {
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
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func containsEither(_ first: String, _ second: String) -> Bool {
        guard !first.isEmpty, !second.isEmpty else { return false }
        return first.contains(second) || second.contains(first)
    }
}
