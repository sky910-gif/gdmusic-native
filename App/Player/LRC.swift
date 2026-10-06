import Foundation

/// 一行歌词
struct LyricLine {
    let time: TimeInterval
    let text: String
    var translation: String?
}

/// LRC 解析：支持一行多个时间标签，并合并翻译歌词。
enum LRCParser {

    static func parse(main: String?, translation: String?) -> [LyricLine] {
        let mainLines = parseRaw(main ?? "").sorted { $0.time < $1.time }
        guard let translation = translation, !translation.isEmpty else {
            return mainLines
        }

        let transLines = parseRaw(translation)

        // 用时间做最近匹配（允许 1 秒误差）
        var result: [LyricLine] = []
        for line in mainLines {
            var line = line
            if let match = transLines.min(by: {
                abs($0.time - line.time) < abs($1.time - line.time)
            }), abs(match.time - line.time) <= 1.0, !match.text.isEmpty {
                line.translation = match.text
            }
            result.append(line)
        }
        return result
    }

    /// 解析原始 LRC，可能产生同一行文本对应多个时间
    private static func parseRaw(_ raw: String) -> [LyricLine] {
        var output: [LyricLine] = []

        for rawLine in raw.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }

            // 提取所有 [mm:ss.xx] 时间标签
            var times: [TimeInterval] = []
            var rest = line

            while rest.hasPrefix("[") {
                let close = rest.firstIndex(of: "]") ?? rest.startIndex
                let tag = String(rest[rest.index(after: rest.startIndex)..<close])

                if let t = parseTime(tag) {
                    times.append(t)
                    rest = String(rest[rest.index(after: close)...])
                } else {
                    // 非时间标签（如 ar:、ti:），跳过这一行
                    break
                }
            }

            let text = rest.trimmingCharacters(in: .whitespaces)
            for t in times {
                output.append(LyricLine(time: t, text: text))
            }
        }

        return output
    }

    /// 解析 "mm:ss.xx" / "mm:ss.xxx"
    private static func parseTime(_ tag: String) -> TimeInterval? {
        let parts = tag.split(whereSeparator: { $0 == ":" || $0 == "." })
        guard parts.count >= 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1])
        else { return nil }

        var fraction: Double = 0
        if parts.count >= 3 {
            let rawFrac = parts[2]
            let divisor = pow(10.0, Double(rawFrac.count))
            fraction = (Double(rawFrac) ?? 0) / divisor
        }

        return minutes * 60 + seconds + fraction
    }
}
