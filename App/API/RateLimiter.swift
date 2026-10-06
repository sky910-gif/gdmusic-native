import Foundation

/// 客户端限流：GD Studio 限制为 5 分钟不超过 50 次请求。
/// 采用滑动窗口记录请求时间，超额时等待最早请求“过期”。
actor APIRateLimiter {

    static let shared = APIRateLimiter()

    private let window: TimeInterval = 5 * 60
    private let maxRequests = 50
    /// 预留一点安全余量，实际最多用到 46 次，避免与服务端计数偏差
    private let safeLimit = 46
    private var timestamps: [Date] = []

    /// 在发请求前调用；若会超额则挂起等待。
    func acquire() async {
        let now = Date()
        // 清理窗口外的旧记录
        timestamps.removeAll { now.timeIntervalSince($0) >= window }

        if timestamps.count >= safeLimit {
            if let oldest = timestamps.first {
                let wait = window - now.timeIntervalSince(oldest)
                if wait > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
            }
            // 醒来后再次清理
            let later = Date()
            timestamps.removeAll { later.timeIntervalSince($0) >= window }
        }

        timestamps.append(Date())
    }
}
