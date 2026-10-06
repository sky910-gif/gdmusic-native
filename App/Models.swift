import Foundation

/// 搜索结果中的一首歌
struct Track: Codable, Identifiable, Hashable {
    /// 注意：这里的 id 是各音源内的曲目 ID（字符串），并非全局唯一
    let trackId: String
    let name: String
    let artist: [String]
    let album: String
    let picId: String
    let lyricId: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case trackId = "id"
        case name, artist, album
        case picId = "pic_id"
        case lyricId = "lyric_id"
        case source
    }

    var id: String { source + ":" + trackId }
    var artistText: String { artist.joined(separator: " / ") }
}

/// 取播放地址的返回
struct PlayURL: Codable {
    let url: String
    let br: Int
    let size: Int64?
}

/// 封面返回
struct PicResult: Codable {
    let url: String
}

/// 歌词返回
struct LyricResult: Codable {
    let lyric: String?
    let tlyric: String?
}

/// 音质
enum Bitrate: Int, CaseIterable {
    case k128 = 128
    case k192 = 192
    case k320 = 320
    case lossless16 = 740
    case lossless24 = 999

    var label: String {
        switch self {
        case .k128: return "128k"
        case .k192: return "192k"
        case .k320: return "320k"
        case .lossless16: return "无损"
        case .lossless24: return "超清无损"
        }
    }
}

/// 音源（稳定源优先）
enum MusicSource: String, CaseIterable {
    case netease, joox, bilibili, tencent, kuwo, ytmusic

    var label: String {
        switch self {
        case .netease: return "网易云"
        case .joox: return "JOOX"
        case .bilibili: return "B站"
        case .tencent: return "QQ音乐"
        case .kuwo: return "酷我"
        case .ytmusic: return "YouTube"
        }
    }
}
