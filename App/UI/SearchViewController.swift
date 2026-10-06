import UIKit

/// 原生搜索页：搜索框（输入防抖）、音源切换、结果列表。
final class SearchViewController: UIViewController {

    private var source: MusicSource = .netease
    private var tracks: [Track] = []
    private var searchTask: Task<Void, Never>?

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let statusLabel = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "GD音乐 Pro"
        view.backgroundColor = .systemGroupedBackground

        setupSearchBar()
        setupTableView()
        setupStatus()
        showHint()
    }

    // MARK: - 搜索栏

    private func setupSearchBar() {
        searchBar.placeholder = "搜索歌曲、歌手、专辑"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        navigationItem.titleView = searchBar

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: source.label,
            style: .plain,
            target: self,
            action: #selector(chooseSource)
        )
    }

    @objc private func chooseSource() {
        let alert = UIAlertController(title: "选择音源", message: nil, preferredStyle: .actionSheet)

        for s in MusicSource.allCases {
            let mark = s == source ? "✓ " : ""
            alert.addAction(UIAlertAction(title: mark + s.label, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.source = s
                self.navigationItem.leftBarButtonItem?.title = s.label
                if let keyword = self.searchBar.text, !keyword.isEmpty {
                    self.performSearch(keyword)
                }
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - 表格

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseID)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupStatus() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
        ])

        activity.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activity)
        NSLayoutConstraint.activate([
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func showHint() {
        statusLabel.text = "搜索喜欢的音乐\n数据来自 GD音乐台（music.gdstudio.xyz）"
        statusLabel.isHidden = false
        tableView.isHidden = true
    }

    // MARK: - 搜索（防抖）

    fileprivate func performSearch(_ keyword: String) {
        let key = keyword.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            searchTask?.cancel()
            tracks = []
            tableView.reloadData()
            showHint()
            return
        }

        // 取消上一次未完成的搜索，实现防抖
        searchTask?.cancel()

        statusLabel.isHidden = true
        tableView.isHidden = false
        activity.startAnimating()

        let src = source
        searchTask = Task { [weak self] in
            // 400ms 防抖窗口
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            do {
                let result = try await GDAPI.search(keyword: key, source: src)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self = self else { return }
                    self.activity.stopAnimating()
                    self.tracks = result
                    self.tableView.reloadData()
                    self.tableView.isHidden = result.isEmpty
                    if result.isEmpty {
                        self.statusLabel.text = "没有找到相关结果"
                        self.statusLabel.isHidden = false
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.activity.stopAnimating()
                    self?.statusLabel.text = error.localizedDescription
                    self?.statusLabel.isHidden = false
                    self?.tableView.isHidden = true
                }
            }
        }
    }
}

// MARK: - UISearchBarDelegate

extension SearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        performSearch(searchText)
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tracks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseID, for:  indexPath) as! TrackCell
        cell.configure(with: tracks[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        searchBar.resignFirstResponder()

        let playerVC = PlayerViewController(
            tracks: tracks,
            startIndex: indexPath.row,
            source: source
        )
        playerVC.modalPresentationStyle = .fullScreen
        present(playerVC, animated: true)
    }
}

// MARK: - 结果 Cell

final class TrackCell: UITableViewCell {

    static let reuseID = "TrackCell"

    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var loadTask: Task<Void, Never>?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 6
        coverView.backgroundColor = .secondarySystemFill
        coverView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverView)

        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 46),
            coverView.heightAnchor.constraint(equalToConstant: 46),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            titleLabel.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        coverView.image = nil
    }

    func configure(with track: Track) {
        titleLabel.text = track.name
        subtitleLabel.text = track.artistText + " · " + track.album

        let source = MusicSource(rawValue: track.source) ?? .netease
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            if let coverURL = try? await GDAPI.coverURL(picId: track.picId, source: source, size: 300) {
                let image = await ImageCache.shared.image(for: coverURL)
                if !Task.isCancelled {
                    await MainActor.run { self?.coverView.image = image }
                }
            }
        }
    }
}
