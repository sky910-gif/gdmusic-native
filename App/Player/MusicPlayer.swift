import Foundation
import AVFoundation
import MediaPlayer

/// 播放模式
enum PlayMode {
    case repeatAll, repeatOne, shuffle
}

/// 原生播放内核：用 AVPlayer 播放搜索结果，维护队列、播放模式、
/// Now Playing 信息与锁屏/车载控制。
final class MusicPlayer: NSObject {

    static let shared = MusicPlayer()

    // 播放队列（显示顺序）
    private(set) var tracks: [Track] = []
    private(set) var currentIndex: Int = 0
    private var mode: PlayMode = .repeatAll
    private var bitrate: Bitrate = .k320

    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var timeObserver: Any?

    /// 当前曲目封面（异步加载后保存）
    private var coverImage: UIImage?

    /// 界面刷新回调（主线程）
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    /// 封面加载完成回调（主线程）
    var onCover: ((UIImage?) -> Void)?

    private var isPreparing = false

    override init() {
        super.init()
        configureObservers()
    }

    // MARK: - 属性

    var currentTrack: Track? {
        tracks.indices.contains(currentIndex) ? tracks[currentIndex] : nil
    }
    var isPlaying: Bool { player.rate != 0 }
    var currentTime: TimeInterval {
        let t = player.currentTime()
        let s = CMTimeGetSeconds(t)
        return s.isFinite ? s : 0
    }
    var duration: TimeInterval {
        guard let item = player.currentItem else { return 0 }
        let d = CMTimeGetSeconds(item.duration)
        return d.isFinite ? d : 0
    }
    var playMode: PlayMode { mode }
    var currentBitrate: Bitrate { bitrate }

    // MARK: - 配置

    private func configureObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 2),
            queue: .main
        ) { [weak self] _ in
            self?.onChange?()
            self?.updateElapsed()
        }

        rateObservation = player.observe(\.rate) { [weak self] _, _ in
            DispatchQueue.main.async { self?.onChange?() }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEnded(_:)),
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    // MARK: - 队列操作

    /// 从搜索结果点歌：建立队列并开始播放
    func start(tracks: [Track], index: Int, bitrate: Bitrate) {
        self.tracks = tracks
        self.currentIndex = index
        self.bitrate = bitrate
        RemoteCommandController.shared.setPlayback(self)
        prepareAndPlay()
    }

    func setBitrate(_ br: Bitrate) {
        bitrate = br
        prepareAndPlay()
    }

    func cycleMode() {
        switch mode {
        case .repeatAll: mode = .repeatOne
        case .repeatOne: mode = .shuffle
        case .shuffle: mode = .repeatAll
        }
        onChange?()
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: TimeInterval) {
        player.seek(
            to: CMTime(seconds: max(0, seconds), preferredTimescale: 1000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func next() { advanceByOne() }
    func previous() {
        if currentTime > 3 {
            seek(to: 0)
        } else {
            backByOne()
        }
    }

    // MARK: - 加载当前曲目

    private func prepareAndPlay() {
        guard let track = currentTrack else { return }
        isPreparing = true
        coverImage = nil
        DispatchQueue.main.async { self.onCover?(nil) }

        Task {
            do {
                // 1. 取播放地址
                let play = try await GDAPI.playURL(
                    trackId: track.trackId,
                    source: MusicSource(rawValue: track.source) ?? .netease,
                    bitrate: bitrate
                )

                // 2. 建立播放项
                guard let url = URL(string: play.url) else {
                    throw APIError.invalidResponse
                }
                let item = AVPlayerItem(url: url)

                await MainActor.run {
                    self.statusObservation?.invalidate()
                    self.statusObservation = item.observe(\.status) { [weak self] item, _ in
                        guard let self = self else { return }
                        switch item.status {
                        case .readyToPlay:
                            self.pushNowPlaying()
                        case .failed:
                            self.reportError(item.error?.localizedDescription ?? "无法播放")
                        default: break
                        }
                    }

                    self.player.replaceCurrentItem(with: item)
                    self.player.play()
                    self.isPreparing = false
                    self.pushNowPlaying()
                    self.onChange?()
                }

                // 3. 异步加载封面并刷新 Now Playing
                let source = MusicSource(rawValue: track.source) ?? .netease
                if let coverURL = try? await GDAPI.coverURL(
                    picId: track.picId, source: source
                ) {
                    let image = await ImageCache.shared.image(for: coverURL)
                    await MainActor.run {
                        self.coverImage = image
                        self.pushNowPlaying()
                        self.onCover?(image)
                        self.onChange?()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isPreparing = false
                    self.reportError(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 队列移动

    private func advanceByOne() {
        guard !tracks.isEmpty else { return }

        if mode == .shuffle, tracks.count > 1 {
            currentIndex = randomIndex(excluding: currentIndex)
        } else {
            currentIndex = (currentIndex + 1) % tracks.count
        }
        prepareAndPlay()
    }

    private func backByOne() {
        guard !tracks.isEmpty else { return }
        var idx = currentIndex - 1
        if idx < 0 { idx += tracks.count }
        currentIndex = idx
        prepareAndPlay()
    }

    private func randomIndex(excluding: Int) -> Int {
        var i = currentIndex
        while i == excluding {
            i = Int.random(in: 0..<tracks.count)
        }
        return i
    }

    // MARK: - 事件

    @objc private func handleEnded(_ note: Notification) {
        guard let item = note.object as? AVPlayerItem,
              item === player.currentItem else { return }

        switch mode {
        case .repeatOne:
            seek(to: 0)
            player.play()
        case .repeatAll, .shuffle:
            advanceByOne()
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw),
            type == .ended
        else { return }

        let options = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
            player.play()
        }
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async {
            self.onError?(message)
            self.onChange?()
        }
    }

    // MARK: - Now Playing

    private func pushNowPlaying() {
        guard let track = currentTrack else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artistText,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
        ]

        if let image = coverImage {
            info[MPMediaItemPropertyArtwork] =
                MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateElapsed() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// 退出时释放锁屏接管
    func deactivate() {
        player.pause()
        RemoteCommandController.shared.setPlayback(nil)
    }
}

// MARK: - RemotePlayback 协议

protocol RemotePlayback: AnyObject {
    func remotePlay()
    func remotePause()
    func remoteNext()
    func remotePrevious()
    func remoteSeek(_ seconds: Double)
}

extension MusicPlayer: RemotePlayback {
    func remotePlay() { play() }
    func remotePause() { pause() }
    func remoteNext() { next() }
    func remotePrevious() { previous() }
    func remoteSeek(_ seconds: Double) { seek(to: seconds) }
}
