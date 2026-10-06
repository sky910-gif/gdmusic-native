import Foundation

/// GD Studio Online Music Platform API 封装。
/// 文档：https://music-api.gdstudio.xyz/api.php
enum GDAPI {

    private static let endpoint = URL(string: "https://music-api.gdstudio.xyz/api.php")!

    // MARK: - 底层请求

    private static func request(
        query: [String: String],
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> Data {
        // 先过客户端限流
        await APIRateLimiter.shared.acquire()

        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 25
        request.setValue("GDMusicPro/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw APIError.rateLimited
            }
            throw APIError.httpStatus(http.statusCode)
        }

        // 服务端异常时可能返回 HTML，这里交由解码阶段报错
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // 打印前一小段便于定位
            throw APIError.decodingFailed(String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - 公开接口

    /// 搜索
    static func search(
        keyword: String,
        source: MusicSource,
        count: Int = 30,
        page: Int = 1
    ) async throws -> [Track] {
        let data = try await request(query: [
            "types": "search",
            "source": source.rawValue,
            "name": keyword,
            "count": String(count),
            "pages": String(page),
        ])
        return try decode([Track].self, from: data)
    }

    /// 取播放地址
    static func playURL(
        trackId: String,
        source: MusicSource,
        bitrate: Bitrate
    ) async throws -> PlayURL {
        let data = try await request(query: [
            "types": "url",
            "source": source.rawValue,
            "id": trackId,
            "br": String(bitrate.rawValue),
        ])
        return try decode(PlayURL.self, from: data)
    }

    /// 取封面地址
    static func coverURL(
        picId: String,
        source: MusicSource,
        size: Int = 500
    ) async throws -> URL {
        let data = try await request(query: [
            "types": "pic",
            "source": source.rawValue,
            "id": picId,
            "size": String(size),
        ])
        let result = try decode(PicResult.self, from: data)
        guard let url = URL(string: result.url) else { throw APIError.invalidResponse }
        return url
    }

    /// 取歌词
    static func lyrics(
        lyricId: String,
        source: MusicSource
    ) async throws -> LyricResult {
        let data = try await request(query: [
            "types": "lyric",
            "source": source.rawValue,
            "id": lyricId,
        ])
        return try decode(LyricResult.self, from: data)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case rateLimited
    case httpStatus(Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务器返回异常"
        case .rateLimited: return "请求过于频繁，请稍后再试"
        case .httpStatus(let code): return "网络错误（\(code)）"
        case .decodingFailed: return "数据解析失败"
        }
    }
}
