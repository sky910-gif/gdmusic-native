import MediaPlayer

/// 锁屏 / 控制中心 / 车载（蓝牙、CarPlay「正在播放」、方向盘按键）控制中心。
final class RemoteCommandController {

    static let shared = RemoteCommandController()

    private weak var playback: RemotePlayback?
    private var didRegister = false

    private init() {}

    func setPlayback(_ playback: RemotePlayback?) {
        self.playback = playback
    }

    func register() {
        guard !didRegister else { return }
        didRegister = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.playback?.remotePlay()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.playback?.remotePause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playback?.remoteNext()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playback?.remotePrevious()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let ev = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.playback?.remoteSeek(ev.positionTime)
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
    }
}
