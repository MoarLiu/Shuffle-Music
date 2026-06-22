import AVFoundation
import Combine
import Foundation
import ShuffleMusicCore

enum ShuffleMusicPlaybackStatus: Equatable {
    case idle
    case loadingCatalog
    case resolvingTrack
    case playing
    case paused
    case stopped
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "待播放"
        case .loadingCatalog:
            return "正在加载歌池"
        case .resolvingTrack:
            return "正在解析音源"
        case .playing:
            return "正在播放"
        case .paused:
            return "已暂停"
        case .stopped:
            return "已停止"
        case .failed:
            return "播放失败"
        }
    }

    var isBusy: Bool {
        switch self {
        case .loadingCatalog, .resolvingTrack:
            return true
        case .idle, .playing, .paused, .stopped, .failed:
            return false
        }
    }

    var isPlaying: Bool {
        self == .playing
    }

    var isPaused: Bool {
        self == .paused
    }
}

struct ShuffleMusicPlayerSnapshot: Equatable {
    var status: ShuffleMusicPlaybackStatus = .idle
    var currentTrack: ShuffleMusicTrack?
    var catalog: [ShuffleMusicTrack] = []
    var canPlayPrevious = false

    var canPlayNext: Bool {
        !catalog.isEmpty
    }

    var playableCount: Int {
        catalog.count
    }
}

struct ShuffleMusicPlaylistSource: Equatable, Hashable {
    let id: Int
    let name: String
    let coverImageURL: URL?

    var detailURL: URL {
        URL(string: "https://music.163.com/api/v6/playlist/detail?id=\(id)&s=0")!
    }

    // Mirrors YesPlayMusic's static byAppleMusic playlist list.
    static let byAppleMusic: [ShuffleMusicPlaylistSource] = [
        ShuffleMusicPlaylistSource(
            id: 5278068783,
            name: "Happy Hits",
            coverImageURL: URL(string: "https://p2.music.126.net/GvYQoflE99eoeGi9jG4Bsw==/109951165375336156.jpg")
        ),
        ShuffleMusicPlaylistSource(
            id: 5277771961,
            name: "中嘻合璧",
            coverImageURL: URL(string: "https://p2.music.126.net/5CJeYN35LnzRDsv5Lcs0-Q==/109951165374966765.jpg")
        ),
        ShuffleMusicPlaylistSource(
            id: 5277965913,
            name: "Heartbreak Pop",
            coverImageURL: URL(string: "https://p1.music.126.net/cPaBXr1wZSg86ddl47AK7Q==/109951165375130918.jpg")
        ),
        ShuffleMusicPlaylistSource(
            id: 5277969451,
            name: "Festival Bangers",
            coverImageURL: URL(string: "https://p2.music.126.net/FDtX55P2NjccDna-LBj9PA==/109951165375065973.jpg")
        ),
        ShuffleMusicPlaylistSource(
            id: 5277778542,
            name: "Bedtime Beats",
            coverImageURL: URL(string: "https://p2.music.126.net/hC0q2dGbOWHVfg4nkhIXPg==/109951165374881177.jpg")
        )
    ]

    // Mirrors YesPlayMusic's fixed home-page chart playlist ids.
    static let yesPlayMusicHomeCharts: [ShuffleMusicPlaylistSource] = [
        ShuffleMusicPlaylistSource(id: 19723756, name: "飙升榜", coverImageURL: nil),
        ShuffleMusicPlaylistSource(id: 180106, name: "UK排行榜周榜", coverImageURL: nil),
        ShuffleMusicPlaylistSource(id: 60198, name: "美国Billboard榜", coverImageURL: nil),
        ShuffleMusicPlaylistSource(id: 3812895, name: "Beatport全球电子舞曲榜", coverImageURL: nil),
        ShuffleMusicPlaylistSource(id: 60131, name: "日本Oricon榜", coverImageURL: nil)
    ]

    static let defaultSources: [ShuffleMusicPlaylistSource] = byAppleMusic + yesPlayMusicHomeCharts
}

enum ShuffleMusicToggleResult: Equatable {
    case starting
    case started(ShuffleMusicTrack)
    case stopped
    case unavailable
}

final class ShuffleMusicFeature: ObservableObject {
    static let defaultTargetCatalogSize = 500

    @Published private(set) var snapshot = ShuffleMusicPlayerSnapshot()

    var onPlaybackFailed: ((ShuffleMusicTrack?, String) -> Void)?
    var onPlaybackAdvanced: ((ShuffleMusicTrack) -> Void)?
    var onPlaybackStarted: ((ShuffleMusicTrack) -> Void)?

    private let playlistSources: [ShuffleMusicPlaylistSource]
    private let targetCatalogSize: Int
    private let maximumRetries = 3
    private var player: AVPlayer?
    private var playbackQueue = ShuffleMusicPlaybackQueue()
    private var currentPlaybackID: UUID?
    private var playbackStatus: ShuffleMusicPlaybackStatus = .idle
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var urlResolver: ShuffleMusicURLResolver?
    private var playlistTrackResolver: ShuffleMusicPlaylistTrackResolver?
    private var retryCount = 0

    init(
        playlistSources: [ShuffleMusicPlaylistSource] = ShuffleMusicPlaylistSource.defaultSources,
        targetCatalogSize: Int = ShuffleMusicFeature.defaultTargetCatalogSize
    ) {
        self.playlistSources = playlistSources
        self.targetCatalogSize = max(targetCatalogSize, 1)
    }

    deinit {
        stopInternal()
    }

    var hasActivePlayback: Bool {
        currentPlaybackID != nil || player != nil || urlResolver != nil || playlistTrackResolver != nil
    }

    @discardableResult
    func toggleRandomPlayback() -> ShuffleMusicToggleResult {
        if playbackStatus.isPlaying {
            pause()
            return .stopped
        }

        if playbackStatus.isPaused {
            resume()
            if let currentTrack = playbackQueue.currentTrack {
                return .started(currentTrack)
            }
            return .starting
        }

        return startRandomPlayback()
    }

    @discardableResult
    func startRandomPlayback() -> ShuffleMusicToggleResult {
        if let track = nextTrack(excluding: nil) {
            retryCount = 0
            play(track, recordHistory: false)
            return .started(track)
        }

        guard !playlistSources.isEmpty else {
            updateSnapshot(status: .failed("没有可用歌单。"))
            return .unavailable
        }

        preparePlaylistCatalogAndPlay()
        return .starting
    }

    @discardableResult
    func playPreviousTrack() -> ShuffleMusicToggleResult {
        guard let previousTrack = playbackQueue.previousTrack() else {
            return startRandomPlayback()
        }
        retryCount = 0
        onPlaybackAdvanced?(previousTrack)
        play(previousTrack, recordHistory: false)
        return .started(previousTrack)
    }

    @discardableResult
    func playNextTrack() -> ShuffleMusicToggleResult {
        guard let nextTrack = nextTrack(excluding: playbackQueue.currentTrack) else {
            return startRandomPlayback()
        }
        retryCount = 0
        onPlaybackAdvanced?(nextTrack)
        play(nextTrack, recordHistory: true)
        return .started(nextTrack)
    }

    @discardableResult
    func playTrack(_ track: ShuffleMusicTrack) -> ShuffleMusicToggleResult {
        guard playbackQueue.catalog.contains(where: { $0.id == track.id }) else {
            return .unavailable
        }
        playbackQueue.removeFromUpcoming(track)
        retryCount = 0
        onPlaybackStarted?(track)
        play(track, recordHistory: true)
        return .started(track)
    }

    private func preparePlaylistCatalogAndPlay() {
        let playbackID = UUID()
        currentPlaybackID = playbackID
        retryCount = 0
        updateSnapshot(status: .loadingCatalog)

        let resolver = ShuffleMusicPlaylistTrackResolver()
        playlistTrackResolver = resolver
        resolver.loadTracks(from: playlistSources, targetCount: targetCatalogSize) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.currentPlaybackID == playbackID else { return }
                self.playlistTrackResolver = nil

                switch result {
                case .success(let tracks):
                    self.playbackQueue.replaceCatalog(tracks)
                    guard let track = self.nextTrack(excluding: nil) else {
                        let message = "默认歌单没有可播放曲目。"
                        self.stopInternal(status: .failed(message))
                        self.onPlaybackFailed?(nil, message)
                        return
                    }
                    self.onPlaybackStarted?(track)
                    self.play(track, recordHistory: false)
                case .failure(let error):
                    self.stopInternal(status: .failed(error.localizedDescription))
                    self.onPlaybackFailed?(nil, error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        stopInternal(status: .stopped)
    }

    func pause() {
        guard playbackStatus.isPlaying else { return }
        player?.pause()
        updateSnapshot(status: .paused)
    }

    func resume() {
        guard player != nil else {
            _ = startRandomPlayback()
            return
        }

        player?.play()
        updateSnapshot(status: .playing)
    }

    @discardableResult
    func togglePlayPause() -> ShuffleMusicToggleResult {
        if playbackStatus.isBusy {
            stop()
            return .stopped
        }

        if playbackStatus.isPlaying {
            pause()
            return .stopped
        }

        if playbackStatus.isPaused {
            resume()
            if let currentTrack = playbackQueue.currentTrack {
                return .started(currentTrack)
            }
            return .starting
        }

        return startRandomPlayback()
    }

    private func stopInternal(status: ShuffleMusicPlaybackStatus = .stopped) {
        currentPlaybackID = nil
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        urlResolver?.cancel()
        urlResolver = nil
        playlistTrackResolver?.cancel()
        playlistTrackResolver = nil
        player?.pause()
        player = nil
        playbackQueue.clearCurrentTrack()
        retryCount = 0
        updateSnapshot(status: status)
    }

    private func play(_ track: ShuffleMusicTrack, recordHistory: Bool) {
        let playbackID = UUID()
        currentPlaybackID = playbackID
        playbackQueue.setCurrentTrack(track, recordHistory: recordHistory)
        updateSnapshot(status: .resolvingTrack)
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        urlResolver?.cancel()
        urlResolver = nil

        let resolver = ShuffleMusicURLResolver()
        urlResolver = resolver
        resolver.resolve(track.externalPlaybackURL) { [weak self] resolvedURL in
            DispatchQueue.main.async {
                guard let self, self.currentPlaybackID == playbackID else { return }
                self.urlResolver = nil
                self.startPlayer(track: track, playbackID: playbackID, url: resolvedURL ?? track.externalPlaybackURL)
            }
        }
    }

    private func startPlayer(track: ShuffleMusicTrack, playbackID: UUID, url: URL) {
        let asset = AVURLAsset(
            url: url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "User-Agent": "Mozilla/5.0",
                    "Referer": "https://music.163.com/"
                ]
            ]
        )
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.volume = 0.45

        statusObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] observedItem, _ in
            guard let self,
                  self.currentPlaybackID == playbackID,
                  item === observedItem
            else {
                return
            }

            if observedItem.status == .failed {
                DispatchQueue.main.async {
                    self.handlePlaybackFailure(
                        track: track,
                        message: observedItem.error?.localizedDescription ?? "网易云外链暂时无法播放。"
                    )
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.advanceAfterNaturalEnd(from: track, playbackID: playbackID)
        }

        self.player = player
        player.play()
        updateSnapshot(status: .playing)
    }

    private func advanceAfterNaturalEnd(from track: ShuffleMusicTrack, playbackID: UUID) {
        guard currentPlaybackID == playbackID else { return }
        guard let nextTrack = nextTrack(excluding: track) else {
            stop()
            return
        }

        retryCount = 0
        onPlaybackAdvanced?(nextTrack)
        play(nextTrack, recordHistory: true)
    }

    private func handlePlaybackFailure(track: ShuffleMusicTrack, message: String) {
        guard hasActivePlayback else { return }

        if retryCount < maximumRetries, let nextTrack = nextTrack(excluding: track) {
            retryCount += 1
            play(nextTrack, recordHistory: false)
            return
        }

        let failedTrack = playbackQueue.currentTrack
        stopInternal(status: .failed(message))
        onPlaybackFailed?(failedTrack, message)
    }

    private func nextTrack(excluding excludedTrack: ShuffleMusicTrack?) -> ShuffleMusicTrack? {
        playbackQueue.nextTrack(excluding: excludedTrack)
    }

    private func updateSnapshot(status: ShuffleMusicPlaybackStatus? = nil) {
        if let status {
            playbackStatus = status
        }
        snapshot = ShuffleMusicPlayerSnapshot(
            status: playbackStatus,
            currentTrack: playbackQueue.currentTrack,
            catalog: playbackQueue.catalog,
            canPlayPrevious: playbackQueue.canPlayPrevious
        )
    }
}

private enum ShuffleMusicPlaylistError: LocalizedError {
    case noTracks

    var errorDescription: String? {
        switch self {
        case .noTracks:
            return "无法从默认歌单加载曲目。"
        }
    }
}

private final class ShuffleMusicPlaylistTrackResolver {
    private let lock = NSLock()
    private var session: URLSession?
    private var playableTrackFilter: ShuffleMusicPlayableTrackFilter?
    private var trackDetailResolver: ShuffleMusicTrackDetailResolver?
    private var isCancelled = false

    func loadTracks(
        from sources: [ShuffleMusicPlaylistSource],
        targetCount: Int,
        completion: @escaping (Result<[ShuffleMusicTrack], Error>) -> Void
    ) {
        guard !sources.isEmpty else {
            completion(.failure(ShuffleMusicPlaylistError.noTracks))
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        let session = URLSession(configuration: configuration)
        self.session = session

        let group = DispatchGroup()
        let resultLock = NSLock()
        var tracksBySource = Array(repeating: [ShuffleMusicTrack](), count: sources.count)

        for (index, source) in sources.enumerated() {
            group.enter()
            var request = URLRequest(url: source.detailURL)
            request.timeoutInterval = 12
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")

            session.dataTask(with: request) { [weak self] data, _, _ in
                defer { group.leave() }
                guard self?.cancelled() == false,
                      let data,
                      let response = try? JSONDecoder().decode(PlaylistDetailResponse.self, from: data),
                      response.code == 200,
                      let playlist = response.playlist
                else {
                    return
                }

                let sourceTitle = playlist.name ?? source.name
                var detailsByID: [Int: ShuffleMusicTrack] = [:]
                for summary in playlist.tracks ?? [] {
                    detailsByID[summary.id] = summary.musicTrack(sourceTitle: sourceTitle)
                }
                let tracks = playlist.trackIds.map { trackID in
                    detailsByID[trackID.id] ?? ShuffleMusicTrack(
                        id: trackID.id,
                        title: "曲目 \(trackID.id)",
                        sourceTitle: sourceTitle
                    )
                }
                resultLock.lock()
                tracksBySource[index] = tracks
                resultLock.unlock()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, self.cancelled() == false else { return }
            session.finishTasksAndInvalidate()
            self.session = nil

            var seen = Set<Int>()
            let candidates = tracksBySource
                .flatMap { $0 }
                .filter { track in
                    seen.insert(track.id).inserted
                }

            guard !candidates.isEmpty else {
                completion(.failure(ShuffleMusicPlaylistError.noTracks))
                return
            }

            let filter = ShuffleMusicPlayableTrackFilter()
            self.setPlayableTrackFilter(filter)
            filter.filter(candidates, targetCount: targetCount) { [weak self, weak filter] playableTracks in
                guard let self, self.cancelled() == false else { return }
                if let filter {
                    self.clearPlayableTrackFilter(filter)
                }

                guard !playableTracks.isEmpty else {
                    completion(.failure(ShuffleMusicPlaylistError.noTracks))
                    return
                }

                let detailResolver = ShuffleMusicTrackDetailResolver()
                self.setTrackDetailResolver(detailResolver)
                detailResolver.enrich(playableTracks) { [weak self, weak detailResolver] enrichedTracks in
                    guard let self, self.cancelled() == false else { return }
                    if let detailResolver {
                        self.clearTrackDetailResolver(detailResolver)
                    }
                    completion(.success(enrichedTracks))
                }
            }
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let filter = playableTrackFilter
        let detailResolver = trackDetailResolver
        playableTrackFilter = nil
        trackDetailResolver = nil
        lock.unlock()
        session?.invalidateAndCancel()
        session = nil
        filter?.cancel()
        detailResolver?.cancel()
    }

    private func cancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    private func setPlayableTrackFilter(_ filter: ShuffleMusicPlayableTrackFilter) {
        lock.lock()
        playableTrackFilter = filter
        lock.unlock()
    }

    private func clearPlayableTrackFilter(_ filter: ShuffleMusicPlayableTrackFilter) {
        lock.lock()
        if playableTrackFilter === filter {
            playableTrackFilter = nil
        }
        lock.unlock()
    }

    private func setTrackDetailResolver(_ resolver: ShuffleMusicTrackDetailResolver) {
        lock.lock()
        trackDetailResolver = resolver
        lock.unlock()
    }

    private func clearTrackDetailResolver(_ resolver: ShuffleMusicTrackDetailResolver) {
        lock.lock()
        if trackDetailResolver === resolver {
            trackDetailResolver = nil
        }
        lock.unlock()
    }

    private struct PlaylistDetailResponse: Decodable {
        let code: Int?
        let playlist: Playlist?
    }

    private struct Playlist: Decodable {
        let name: String?
        let trackIds: [TrackID]
        let tracks: [ShuffleMusicTrackSummary]?
    }

    private struct TrackID: Decodable {
        let id: Int
    }
}

private struct ShuffleMusicTrackSummary: Decodable {
    let id: Int
    let name: String?
    private let ar: [Artist]?
    private let artists: [Artist]?
    private let al: Album?
    private let album: Album?

    func musicTrack(sourceTitle: String?) -> ShuffleMusicTrack {
        let artistNames = (ar ?? artists ?? []).map(\.name).filter { !$0.isEmpty }
        let albumInfo = al ?? album
        return ShuffleMusicTrack(
            id: id,
            title: name ?? "曲目 \(id)",
            artistNames: artistNames,
            albumTitle: albumInfo?.name,
            coverImageURL: albumInfo?.picUrl,
            sourceTitle: sourceTitle
        )
    }

    private struct Artist: Decodable {
        let name: String
    }

    private struct Album: Decodable {
        let name: String?
        let picUrl: URL?
    }
}

private final class ShuffleMusicTrackDetailResolver {
    private let lock = NSLock()
    private var session: URLSession?
    private var isCancelled = false

    func enrich(_ tracks: [ShuffleMusicTrack], completion: @escaping ([ShuffleMusicTrack]) -> Void) {
        guard !tracks.isEmpty else {
            completion([])
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 18
        let session = URLSession(configuration: configuration)
        self.session = session

        let batches = stride(from: 0, to: tracks.count, by: 80).map { start in
            Array(tracks[start..<min(start + 80, tracks.count)])
        }
        let group = DispatchGroup()
        let resultLock = NSLock()
        var detailTracksByID: [Int: ShuffleMusicTrack] = [:]

        for batch in batches {
            guard let url = Self.detailURL(for: batch.map(\.id)) else { continue }
            group.enter()
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")

            session.dataTask(with: request) { [weak self] data, _, _ in
                defer { group.leave() }
                guard self?.cancelled() == false,
                      let data,
                      let response = try? JSONDecoder().decode(SongDetailResponse.self, from: data)
                else {
                    return
                }

                let details = response.songs.map { $0.musicTrack(sourceTitle: nil) }
                resultLock.lock()
                for detail in details {
                    detailTracksByID[detail.id] = detail
                }
                resultLock.unlock()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard self?.cancelled() == false else { return }
            session.finishTasksAndInvalidate()
            self?.session = nil

            let enriched = tracks.map { track in
                guard let detail = detailTracksByID[track.id] else { return track }
                return track.mergingMetadata(from: detail)
            }
            completion(enriched)
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
        session?.invalidateAndCancel()
        session = nil
    }

    private func cancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    private static func detailURL(for ids: [Int]) -> URL? {
        var components = URLComponents(string: "https://music.163.com/api/song/detail")
        components?.queryItems = [
            URLQueryItem(name: "ids", value: "[\(ids.map(String.init).joined(separator: ","))]")
        ]
        return components?.url
    }

    private struct SongDetailResponse: Decodable {
        let songs: [ShuffleMusicTrackSummary]
    }
}

private final class ShuffleMusicPlayableTrackFilter: NSObject, URLSessionTaskDelegate {
    private let stateQueue = DispatchQueue(label: "shuffle-music.playability")
    private let maximumConcurrentRequests = 8
    private var session: URLSession?
    private var candidates: [ShuffleMusicTrack] = []
    private var targetCount = 1
    private var nextIndex = 0
    private var activeTaskCount = 0
    private var playableTracks: [ShuffleMusicTrack] = []
    private var taskTracks: [Int: ShuffleMusicTrack] = [:]
    private var redirectURLs: [Int: URL] = [:]
    private var completion: (([ShuffleMusicTrack]) -> Void)?
    private var isCancelled = false

    func filter(
        _ candidates: [ShuffleMusicTrack],
        targetCount: Int,
        completion: @escaping ([ShuffleMusicTrack]) -> Void
    ) {
        stateQueue.async {
            guard !candidates.isEmpty else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

            self.session = session
            self.candidates = candidates
            self.targetCount = max(targetCount, 1)
            self.completion = completion
            self.startMoreRequests()
        }
    }

    func cancel() {
        stateQueue.async {
            self.isCancelled = true
            self.completion = nil
            self.taskTracks.removeAll()
            self.redirectURLs.removeAll()
            self.session?.invalidateAndCancel()
            self.session = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        stateQueue.async {
            self.redirectURLs[task.taskIdentifier] = request.url
        }
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateQueue.async {
            guard !self.isCancelled, self.completion != nil else { return }
            let track = self.taskTracks.removeValue(forKey: task.taskIdentifier)
            let redirectURL = self.redirectURLs.removeValue(forKey: task.taskIdentifier)
            self.activeTaskCount = max(self.activeTaskCount - 1, 0)

            if let track, ShuffleMusicTrack.isPlayableExternalRedirectURL(redirectURL) {
                self.playableTracks.append(track)
            }

            if self.playableTracks.count >= self.targetCount {
                self.finish(with: Array(self.playableTracks.prefix(self.targetCount)))
                return
            }

            self.startMoreRequests()
        }
    }

    private func startMoreRequests() {
        guard !isCancelled, let session, completion != nil else { return }

        while activeTaskCount < maximumConcurrentRequests,
              nextIndex < candidates.count,
              playableTracks.count < targetCount {
            let track = candidates[nextIndex]
            nextIndex += 1

            var request = URLRequest(url: track.externalPlaybackURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 8
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")

            let task = session.dataTask(with: request)
            taskTracks[task.taskIdentifier] = track
            activeTaskCount += 1
            task.resume()
        }

        if nextIndex >= candidates.count, activeTaskCount == 0 {
            finish(with: playableTracks)
        }
    }

    private func finish(with tracks: [ShuffleMusicTrack]) {
        guard let completion else { return }
        self.completion = nil
        isCancelled = true
        taskTracks.removeAll()
        redirectURLs.removeAll()
        session?.invalidateAndCancel()
        session = nil

        DispatchQueue.main.async {
            completion(tracks)
        }
    }
}

private final class ShuffleMusicURLResolver: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var session: URLSession?
    private var redirectURL: URL?
    private var completion: ((URL?) -> Void)?

    func resolve(_ url: URL, completion: @escaping (URL?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        lock.lock()
        self.completion = completion
        self.session = session
        lock.unlock()

        session.dataTask(with: request) { [weak self] _, response, _ in
            guard let self else { return }
            let resolvedURL = self.resolvedRedirectURL() ?? response?.url ?? url
            self.finish(with: ShuffleMusicTrack.preferredHTTPSPlaybackURL(from: resolvedURL))
        }.resume()
    }

    func cancel() {
        lock.lock()
        completion = nil
        redirectURL = nil
        let session = session
        self.session = nil
        lock.unlock()

        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        redirectURL = request.url
        lock.unlock()
        completionHandler(nil)
    }

    private func resolvedRedirectURL() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return redirectURL
    }

    private func finish(with url: URL?) {
        lock.lock()
        let completion = completion
        self.completion = nil
        redirectURL = nil
        let session = session
        self.session = nil
        lock.unlock()

        session?.finishTasksAndInvalidate()
        completion?(url)
    }
}
