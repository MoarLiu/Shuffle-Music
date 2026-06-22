import Foundation

public struct ShuffleMusicPlaybackQueue {
    public private(set) var catalog: [ShuffleMusicTrack] = []
    public private(set) var currentTrack: ShuffleMusicTrack?

    private var upcomingTracks: [ShuffleMusicTrack] = []
    private var playedHistory: [ShuffleMusicTrack] = []

    public init() {}

    public var canPlayPrevious: Bool {
        !playedHistory.isEmpty
    }

    public mutating func replaceCatalog(_ tracks: [ShuffleMusicTrack]) {
        catalog = tracks
        upcomingTracks = []
        playedHistory = []
        currentTrack = nil
    }

    public mutating func clearCurrentTrack() {
        currentTrack = nil
    }

    public mutating func removeFromUpcoming(_ track: ShuffleMusicTrack) {
        upcomingTracks.removeAll { $0.id == track.id }
    }

    public mutating func setCurrentTrack(_ track: ShuffleMusicTrack, recordHistory: Bool, historyLimit: Int = 80) {
        if recordHistory, let currentTrack, currentTrack != track {
            playedHistory.append(currentTrack)
            if playedHistory.count > historyLimit {
                playedHistory.removeFirst(playedHistory.count - historyLimit)
            }
        }
        currentTrack = track
    }

    public mutating func previousTrack() -> ShuffleMusicTrack? {
        guard let previousTrack = playedHistory.popLast() else {
            return nil
        }
        if let currentTrack, currentTrack != previousTrack {
            upcomingTracks.insert(currentTrack, at: 0)
        }
        return previousTrack
    }

    public mutating func nextTrack(
        excluding excludedTrack: ShuffleMusicTrack?,
        shuffle: ([ShuffleMusicTrack]) -> [ShuffleMusicTrack] = { $0.shuffled() }
    ) -> ShuffleMusicTrack? {
        guard !catalog.isEmpty else { return nil }

        if upcomingTracks.isEmpty {
            refillUpcomingTracks(excluding: excludedTrack, shuffle: shuffle)
        }
        if upcomingTracks.first == excludedTrack, upcomingTracks.count > 1 {
            upcomingTracks.append(upcomingTracks.removeFirst())
        }
        return upcomingTracks.isEmpty ? nil : upcomingTracks.removeFirst()
    }

    private mutating func refillUpcomingTracks(
        excluding excludedTrack: ShuffleMusicTrack?,
        shuffle: ([ShuffleMusicTrack]) -> [ShuffleMusicTrack]
    ) {
        upcomingTracks = shuffle(catalog)
        if let excludedTrack, upcomingTracks.first == excludedTrack, upcomingTracks.count > 1 {
            upcomingTracks.append(upcomingTracks.removeFirst())
        }
    }
}
