import AVFoundation

/// 配置“播放类”音频会话：静音开关不影响、锁屏/后台不中断。
enum AudioSession {

    static func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            NSLog("音频会话激活失败: \(error)")
        }
    }
}
