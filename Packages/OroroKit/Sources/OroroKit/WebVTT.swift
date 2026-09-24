import Foundation

/// A parsed WebVTT subtitle file.
///
/// Ororo's HLS streams carry no subtitle tracks; subtitles are separate .vtt
/// files. The player draws them itself, which is also what makes dual
/// subtitles (two languages at once) possible.
public struct SubtitleTrack: Sendable {
    public struct Cue: Hashable, Sendable {
        public let start: TimeInterval
        public let end: TimeInterval
        public let text: String
    }

    public let cues: [Cue]

    public init(cues: [Cue]) {
        self.cues = cues.sorted { $0.start < $1.start }
    }

    /// Parses WebVTT. Also accepts SRT-style comma decimals, since
    /// user-uploaded subtitles are not always clean.
    public init(webVTT source: String) {
        var cues: [Cue] = []
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        let blocks = normalized.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let first = lines[0]
            if first.hasPrefix("NOTE") || first.hasPrefix("STYLE") || first.hasPrefix("REGION") { continue }

            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = SubtitleTrack.parseTimestamp(parts[0]),
                  // Cue settings ("align:start line:90%") follow the end time.
                  let endToken = parts[1].split(separator: " ").first,
                  let end = SubtitleTrack.parseTimestamp(String(endToken)),
                  end > start else { continue }

            let text = lines[(timingIndex + 1)...]
                .map(SubtitleTrack.stripMarkup)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !text.isEmpty else { continue }
            cues.append(Cue(start: start, end: end, text: text))
        }
        self.init(cues: cues)
    }

    /// Text on screen at `time`, joining overlapping cues.
    public func text(at time: TimeInterval) -> String? {
        // Last cue starting at or before `time`.
        var low = 0, high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        var active: [String] = []
        var index = low - 1
        // Walk back over earlier cues that may still be showing. Cues are
        // short, so a few seconds of look-back covers real-world overlaps.
        while index >= 0, time - cues[index].start < 30 {
            if cues[index].end > time { active.append(cues[index].text) }
            index -= 1
        }
        return active.isEmpty ? nil : active.reversed().joined(separator: "\n")
    }

    static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let token = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let fields = token.split(separator: ":")
        guard (2...3).contains(fields.count) else { return nil }
        var seconds: TimeInterval = 0
        for field in fields {
            guard let value = Double(field) else { return nil }
            seconds = seconds * 60 + value
        }
        return seconds
    }

    /// Removes WebVTT tags (<i>, <c.yellow>, <00:01.000>), SSA overrides
    /// ({\an8}) and the common HTML entities.
    static func stripMarkup(_ line: String) -> String {
        var result = ""
        var depth = 0
        var brace = 0
        for char in line {
            switch char {
            case "<": depth += 1
            case ">" where depth > 0: depth -= 1
            case "{": brace += 1
            case "}" where brace > 0: brace -= 1
            default:
                if depth == 0 && brace == 0 { result.append(char) }
            }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lrm;", with: "")
            .replacingOccurrences(of: "&rlm;", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
