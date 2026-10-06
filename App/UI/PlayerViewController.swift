import UIKit
import AVKit

/// 全屏原生播放页：封面 / 歌词（可切换）、进度、上下首、播放模式、音质、AirPlay。
final class PlayerViewController: UIViewController {

    private let initialTracks: [Track]
    private let startIndex: Int
    private let source: MusicSource

    private var lyrics: [LyricLine] = []
    private var activeLyricIndex: Int = -1
    private var showsLyrics = true

    // 顶部
    private let closeButton = UIButton(type: .system)
    private let sourceLabel = UILabel()

    // 封面 / 歌词
    private let coverImageView = UIImageView()
    private let lyricsTableView = UITableView(frame: .zero, style: .plain)

    // 信息
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()

    // 进度
    private let currentLabel = UILabel()
    private let durationLabel = UILabel()
    private let slider = UISlider()
    private var isScrubbing = false

    // 控制
    private let modeButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let airplayView = AVRoutePickerView()

    private var hasLoadedLyricsForTrackId: String?

    // MARK: - 初始化

    init(tracks: [Track], startIndex: Int, source: MusicSource) {
        self.initialTracks = tracks
        self.startIndex = startIndex
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackground()
        setupTop()
        setupArtworkAndLyrics()
        setupInfo()
        setupProgress()
        setupControls()

        MusicPlayer.shared.onChange = { [weak self] in
            self?.refresh()
        }
        MusicPlayer.shared.onError = { [weak self] message in
            let alert = UIAlertController(title: "无法播放", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            self?.present(alert, animated: true)
        }
        MusicPlayer.shared.onCover = { [weak self] image in
            self?.coverImageView.image = image
        }

        MusicPlayer.shared.start(
            tracks: initialTracks,
            index: startIndex,
            bitrate: .k320
        )
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            MusicPlayer.shared.deactivate()
        }
    }

    // MARK: - 背景

    private func setupBackground() {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.16, green: 0.11, blue: 0.22, alpha: 1).cgColor,
            UIColor(red: 0.04, green: 0.03, blue: 0.06, alpha: 1).cgColor,
        ]
        gradient.frame = view.bounds
        gradient.name = "bg"
        view.layer.insertSublayer(gradient, at: 0)
        view.backgroundColor = UIColor(red: 0.05, green: 0.04, blue: 0.07, alpha: 1)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.first(where: { $0.name == "bg" })?.frame = view.bounds
    }

    // MARK: - 顶部

    private func setupTop() {
        closeButton.tintColor = .white
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: cfg), for: .normal)
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        sourceLabel.text = source.label
        sourceLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        sourceLabel.font = .systemFont(ofSize: 13, weight: .medium)
        sourceLabel.textAlignment = .center
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sourceLabel)
    }

    // MARK: - 封面 / 歌词

    private func setupArtworkAndLyrics() {
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 16
        coverImageView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        coverImageView.translatesAutoresizingMaskIntoConstraints = false

        // 点击封面切换到歌词
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleView))
        coverImageView.isUserInteractionEnabled = true
        coverImageView.addGestureRecognizer(tap)
        view.addSubview(coverImageView)

        lyricsTableView.dataSource = self
        lyricsTableView.delegate = self
        lyricsTableView.register(LyricCell.self, forCellReuseIdentifier: LyricCell.reuseID)
        lyricsTableView.backgroundColor = .clear
        lyricsTableView.separatorStyle = .none
        lyricsTableView.showsVerticalScrollIndicator = false
        lyricsTableView.translatesAutoresizingMaskIntoConstraints = false

        // 点击歌词区域切回封面
        let lyricTap = UITapGestureRecognizer(target: self, action: #selector(toggleView))
        lyricsTableView.addGestureRecognizer(lyricTap)
        view.addSubview(lyricsTableView)
    }

    @objc private func toggleView() {
        showsLyrics.toggle()
        updateCenterView()
    }

    private func updateCenterView() {
        coverImageView.isHidden = showsLyrics
        lyricsTableView.isHidden = !showsLyrics
    }

    // MARK: - 信息

    private func setupInfo() {
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        artistLabel.font = .systemFont(ofSize: 15)
        artistLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        artistLabel.numberOfLines = 1
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(artistLabel)
    }

    // MARK: - 进度

    private func setupProgress() {
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        slider.setThumbImage(thumbImage(), for: .normal)
        slider.addTarget(self, action: #selector(scrubStart), for: .touchDown)
        slider.addTarget(self, action: #selector(scrubChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(scrubEnd), for: [.touchUpInside, .touchUpOutside])
        slider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(slider)

        currentLabel.font = .systemFont(ofSize: 11)
        currentLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        currentLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(currentLabel)

        durationLabel.font = .systemFont(ofSize: 11)
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        durationLabel.textAlignment = .right
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(durationLabel)
    }

    @objc private func scrubStart() { isScrubbing = true }
    @objc private func scrubChanged() {
        let dur = MusicPlayer.shared.duration
        currentLabel.text = formatTime(dur * Double(slider.value))
    }
    @objc private func scrubEnd() {
        let dur = MusicPlayer.shared.duration
        MusicPlayer.shared.seek(to: dur * Double(slider.value))
        isScrubbing = false
    }

    private func thumbImage() -> UIImage {
        let size = CGSize(width: 11, height: 11)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }
    }

    // MARK: - 控制按钮

    private func setupControls() {
        let large = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        let medium = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        let play = UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)

        modeButton.setImage(UIImage(systemName: "repeat", withConfiguration: medium), for: .normal)
        previousButton.setImage(UIImage(systemName: "backward.fill", withConfiguration: large), for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: large), for: .normal)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: play), for: .normal)

        for b in [modeButton, previousButton, playButton, nextButton] {
            b.tintColor = .white
            b.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(b)
        }

        modeButton.addTarget(self, action: #selector(modeTapped), for: .touchUpInside)
        previousButton.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        // 长按模式按钮选音质
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(modeLongPress))
        modeButton.addGestureRecognizer(longPress)

        airplayView.tintColor = .white
        airplayView.activeTintColor = UIColor.white.withAlphaComponent(0.6)
        airplayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(airplayView)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            sourceLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            sourceLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            coverImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coverImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            coverImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.62),
            coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor),

            lyricsTableView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lyricsTableView.topAnchor.constraint(equalTo: coverImageView.topAnchor),
            lyricsTableView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.86),
            lyricsTableView.heightAnchor.constraint(equalTo: coverImageView.heightAnchor),

            titleLabel.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 26),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            currentLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 22),
            currentLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            currentLabel.widthAnchor.constraint(equalToConstant: 42),

            durationLabel.centerYAnchor.constraint(equalTo: currentLabel.centerYAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            durationLabel.widthAnchor.constraint(equalToConstant: 42),

            slider.centerYAnchor.constraint(equalTo: currentLabel.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: currentLabel.trailingAnchor, constant: 8),
            slider.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),

            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -36),

            previousButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            previousButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -30),

            nextButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            nextButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 30),

            modeButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            modeButton.trailingAnchor.constraint(equalTo: previousButton.leadingAnchor, constant: -26),

            airplayView.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            airplayView.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 26),
            airplayView.widthAnchor.constraint(equalToConstant: 26),
            airplayView.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func modeTapped() { MusicPlayer.shared.cycleMode() }
    @objc private func previousTapped() { MusicPlayer.shared.previous() }
    @objc private func nextTapped() { MusicPlayer.shared.next() }
    @objc private func playTapped() {
        if MusicPlayer.shared.isPlaying { MusicPlayer.shared.pause() }
        else { MusicPlayer.shared.play() }
    }

    @objc private func modeLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began else { return }
        let alert = UIAlertController(title: "选择音质", message: "无损音源占用更多流量", preferredStyle: .actionSheet)
        for br in Bitrate.allCases {
            let mark = MusicPlayer.shared.currentBitrate == br ? "✓ " : ""
            alert.addAction(UIAlertAction(title: mark + br.label, style: .default) { _ in
                MusicPlayer.shared.setBitrate(br)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - 刷新

    private func refresh() {
        let track = MusicPlayer.shared.currentTrack
        titleLabel.text = track?.name
        artistLabel.text = track?.artistText

        durationLabel.text = formatTime(MusicPlayer.shared.duration)

        let cfg = UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
        playButton.setImage(
            UIImage(systemName: MusicPlayer.shared.isPlaying ? "pause.fill" : "play.fill",
                    withConfiguration: cfg),
            for: .normal
        )
        updateModeIcon()

        if !isScrubbing {
            let d = MusicPlayer.shared.duration
            slider.value = d > 0 ? Float(MusicPlayer.shared.currentTime / d) : 0
            currentLabel.text = formatTime(MusicPlayer.shared.currentTime)
        }

        // 切歌后加载歌词
        if let track = track, hasLoadedLyricsForTrackId != track.id {
            hasLoadedLyricsForTrackId = track.id
            loadLyrics(track)
        }

        // 歌词高亮
        updateActiveLyric()
    }

    private func updateModeIcon() {
        let medium = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        let icon: String
        switch MusicPlayer.shared.playMode {
        case .repeatAll: icon = "repeat"
        case .repeatOne: icon = "repeat.1"
        case .shuffle: icon = "shuffle"
        }
        modeButton.setImage(UIImage(systemName: icon, withConfiguration: medium), for: .normal)
    }

    private func loadLyrics(_ track: Track) {
        lyrics = []
        activeLyricIndex = -1
        lyricsTableView.reloadData()

        let src = MusicSource(rawValue: track.source) ?? .netease
        Task { [weak self] in
            if let result = try? await GDAPI.lyrics(lyricId: track.lyricId, source: src) {
                await MainActor.run {
                    guard let self = self,
                          MusicPlayer.shared.currentTrack?.id == track.id
                    else { return }
                    self.lyrics = LRCParser.parse(main: result.lyric, translation: result.tlyric)
                    self.lyricsTableView.reloadData()
                    self.updateActiveLyric()
                }
            }
        }
    }

    /// 根据当前播放时间找到应高亮的歌词行
    private func updateActiveLyric() {
        guard !lyrics.isEmpty else { return }
        let time = MusicPlayer.shared.currentTime

        // 最后一行时间 <= time 的行
        var index = -1
        for (i, line) in lyrics.enumerated() {
            if line.time <= time + 0.2 { index = i } else { break }
        }

        guard index != activeLyricIndex else { return }
        activeLyricIndex = index

        for i in 0..<lyrics.count {
            if let cell = lyricsTableView.cellForRow(at: IndexPath(row: i, section: 0)) as? LyricCell {
                cell.setActive(i == index)
            }
        }

        if index >= 0 {
            lyricsTableView.scrollToRow(
                at: IndexPath(row: index, section: 0),
                at: .middle,
                animated: true
            )
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - 歌词表格

extension PlayerViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        lyrics.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LyricCell.reuseID, for: indexPath) as! LyricCell
        cell.configure(with: lyrics[indexPath.row])
        cell.setActive(indexPath.row == activeLyricIndex)
        return cell
    }

    /// 拖动后暂停自动滚动一小段时间（简化：不处理，靠下次高亮拉回）
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {}
}

// MARK: - 歌词 Cell

final class LyricCell: UITableViewCell {

    static let reuseID = "LyricCell"

    private let label = UILabel()
    private let translationLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.45)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        translationLabel.textAlignment = .center
        translationLabel.font = .systemFont(ofSize: 13)
        translationLabel.textColor = UIColor.white.withAlphaComponent(0.35)
        translationLabel.numberOfLines = 0
        translationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(translationLabel)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            translationLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 3),
            translationLabel.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            translationLabel.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            translationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with line: LyricLine) {
        label.text = line.text
        if let trans = line.translation, !trans.isEmpty {
            translationLabel.text = trans
            translationLabel.isHidden = false
        } else {
            translationLabel.isHidden = true
        }
    }

    func setActive(_ active: Bool) {
        label.textColor = active
            ? UIColor.white
            : UIColor.white.withAlphaComponent(0.45)
        label.font = active
            ? .systemFont(ofSize: 17, weight: .bold)
            : .systemFont(ofSize: 16, weight: .medium)
        translationLabel.textColor = active
            ? UIColor.white.withAlphaComponent(0.7)
            : UIColor.white.withAlphaComponent(0.35)
    }
}
