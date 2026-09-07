//
//  Song.swift
//  LiteMusic
//
//  歌曲数据模型：对应网易云音乐接口返回的歌曲结构
//

import Foundation

// MARK: - 歌曲

/// 歌曲模型，对应网易云 API 中的 song 对象
struct Song: Identifiable, Decodable, Hashable {
    /// 歌曲 ID
    let id: Int
    /// 歌曲名
    let name: String
    /// 歌手列表（网易云字段名：ar）
    let ar: [Artist]
    /// 专辑（网易云字段名：al）
    let al: Album
    /// 时长，单位毫秒（网易云字段名：dt，部分接口为 duration）
    let dt: Int

    enum CodingKeys: String, CodingKey {
        case id, name, ar, al, dt, duration
    }

    init(id: Int, name: String, ar: [Artist], al: Album, dt: Int) {
        self.id = id
        self.name = name
        self.ar = ar
        self.al = al
        self.dt = dt
    }

    /// 兼容两种时长字段：优先取 dt，缺失时退回 duration
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        ar = (try? c.decode([Artist].self, forKey: .ar)) ?? []
        al = (try? c.decode(Album.self, forKey: .al)) ?? Album(id: 0, name: "未知专辑", picUrl: nil)
        if let d = try? c.decode(Int.self, forKey: .dt) {
            dt = d
        } else if let d = try? c.decode(Int.self, forKey: .duration) {
            dt = d
        } else {
            dt = 0
        }
    }

    /// 歌手名（多个歌手用 " / " 连接）
    var artistName: String {
        ar.isEmpty ? "未知歌手" : ar.map { $0.name }.joined(separator: " / ")
    }

    /// 专辑名
    var albumName: String { al.name }

    /// 时长（秒）
    var duration: TimeInterval { TimeInterval(dt) / 1000.0 }

    /// 封面图地址（空字符串按 nil 处理）
    var coverURLString: String? {
        guard let url = al.picUrl?.trimmingCharacters(in: .whitespaces), !url.isEmpty else { return nil }
        return url
    }

    /// 格式化时长文本，例如 "3:45"
    var durationText: String {
        let total = max(0, Int(duration))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 歌手

/// 歌手
struct Artist: Codable, Hashable {
    let id: Int
    let name: String
}

// MARK: - 专辑

/// 专辑
struct Album: Codable, Hashable {
    let id: Int
    let name: String
    let picUrl: String?
}

// MARK: - 歌词

/// 单行歌词
struct LyricLine: Identifiable {
    let id = UUID()
    /// 时间点（秒）
    let time: TimeInterval
    /// 歌词文本
    let text: String
}

/// LRC 歌词解析器
enum LRC {
    /// 解析 LRC 格式歌词，返回按时间升序排列的歌词行数组
    /// 支持形如 [00:12.34]、[01:23]、[01:23.5] 的时间标签，一行多标签也会展开
    static func parse(_ lrcText: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = "\\[(\\d{1,2}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return lines }

        for raw in lrcText.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, options: [], range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }

            // 歌词文本：取最后一个时间标签之后的内容
            let last = matches.last!
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)

            for match in matches {
                let tag = ns.substring(with: match.range)        // 例如 "[00:12.34]"
                let inner = tag.dropFirst().dropLast()           // 去掉首尾的 [ 和 ]
                let parts = inner.split(whereSeparator: { $0 == ":" || $0 == "." })
                guard parts.count >= 2,
                      let minutes = Int(parts[0]),
                      let seconds = Int(parts[1]) else { continue }

                var time = Double(minutes * 60 + seconds)
                if parts.count >= 3, let frac = Double(parts[2]) {
                    // 毫秒换算为秒的小数部分，例如 "34" -> 0.34, "5" -> 0.5
                    time += frac / pow(10.0, Double(parts[2].count))
                }
                lines.append(LyricLine(time: time, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
