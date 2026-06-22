import Foundation
@testable import ShuffleMusicCore

@discardableResult
func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
    if condition() {
        return true
    }
    fatalError(message)
}

func makeTracks(_ ids: Int...) -> [ShuffleMusicTrack] {
    ids.map { id in
        ShuffleMusicTrack(id: id, title: "Track \(id)")
    }
}

func testNextTrackRefillsAndAvoidsExcludedFirstTrack() {
    var queue = ShuffleMusicPlaybackQueue()
    let tracks = makeTracks(1, 2, 3)
    queue.replaceCatalog(tracks)

    let next = queue.nextTrack(excluding: tracks[0], shuffle: { $0 })

    expect(next == tracks[1], "Expected queue to avoid repeating the excluded first track.")
}

func testPreviousTrackReturnsHistoryAndQueuesCurrentTrack() {
    var queue = ShuffleMusicPlaybackQueue()
    let tracks = makeTracks(1, 2, 3)
    queue.replaceCatalog(tracks)
    queue.setCurrentTrack(tracks[0], recordHistory: false)
    queue.setCurrentTrack(tracks[1], recordHistory: true)

    guard let previous = queue.previousTrack() else {
        fatalError("Expected previous track.")
    }
    queue.setCurrentTrack(previous, recordHistory: false)
    let next = queue.nextTrack(excluding: previous, shuffle: { _ in [] })

    expect(previous == tracks[0], "Expected previous track from history.")
    expect(next == tracks[1], "Expected current track to be queued after going back.")
}

func testHistoryLimitKeepsMostRecentTracks() {
    var queue = ShuffleMusicPlaybackQueue()
    let tracks = makeTracks(0, 1, 2, 3)
    queue.replaceCatalog(tracks)
    queue.setCurrentTrack(tracks[0], recordHistory: false)
    queue.setCurrentTrack(tracks[1], recordHistory: true, historyLimit: 2)
    queue.setCurrentTrack(tracks[2], recordHistory: true, historyLimit: 2)
    queue.setCurrentTrack(tracks[3], recordHistory: true, historyLimit: 2)

    expect(queue.previousTrack() == tracks[2], "Expected newest history item first.")
    expect(queue.previousTrack() == tracks[1], "Expected older retained history item second.")
    expect(queue.previousTrack() == nil, "Expected oldest history item to be trimmed.")
}

func testRemoveFromUpcomingPreventsDuplicateManualSelection() {
    var queue = ShuffleMusicPlaybackQueue()
    let tracks = makeTracks(1, 2, 3)
    queue.replaceCatalog(tracks)
    expect(queue.nextTrack(excluding: nil, shuffle: { $0 }) == tracks[0], "Expected first queued track.")

    queue.removeFromUpcoming(tracks[1])

    expect(queue.nextTrack(excluding: nil, shuffle: { $0 }) == tracks[2], "Expected removed track to be skipped.")
}

func testMergingMetadataDoesNotReplaceExistingTitleWithEmptyDetailTitle() {
    let track = ShuffleMusicTrack(
        id: 42,
        title: "Original Title",
        artistNames: ["Original Artist"],
        albumTitle: "Original Album",
        coverImageURL: URL(string: "https://example.com/original.jpg"),
        sourceTitle: "Source"
    )
    let detail = ShuffleMusicTrack(
        id: 42,
        title: "   ",
        artistNames: ["Detail Artist"],
        albumTitle: nil,
        coverImageURL: nil,
        sourceTitle: nil
    )

    let merged = track.mergingMetadata(from: detail)

    expect(merged.title == "Original Title", "Expected empty detail title not to replace existing title.")
    expect(merged.artistNames == ["Detail Artist"], "Expected detail artist metadata to win.")
    expect(merged.albumTitle == "Original Album", "Expected existing album metadata to remain.")
    expect(merged.sourceTitle == "Source", "Expected existing source metadata to remain.")
}

func testMergingMetadataUsesNonEmptyDetailTitle() {
    let track = ShuffleMusicTrack(id: 42, title: "Original Title")
    let detail = ShuffleMusicTrack(id: 42, title: "Detail Title")

    expect(track.mergingMetadata(from: detail).title == "Detail Title", "Expected non-empty detail title to win.")
}

func testPreferredHTTPSPlaybackURLOnlyChangesNetEaseAudioHost() {
    let insecureURL = URL(string: "http://m10.music.126.net/song.mp3")!
    let otherURL = URL(string: "http://example.com/song.mp3")!

    expect(ShuffleMusicTrack.preferredHTTPSPlaybackURL(from: insecureURL).scheme == "https", "Expected NetEase audio URL to prefer https.")
    expect(ShuffleMusicTrack.preferredHTTPSPlaybackURL(from: otherURL) == otherURL, "Expected non-NetEase URL to be unchanged.")
}

func testPlayableExternalRedirectURLRequiresNetEaseAudioHost() {
    expect(ShuffleMusicTrack.isPlayableExternalRedirectURL(URL(string: "https://m10.music.126.net/song.mp3")), "Expected NetEase audio URL to be playable.")
    expect(!ShuffleMusicTrack.isPlayableExternalRedirectURL(URL(string: "https://music.163.com/song?id=1")), "Expected NetEase web URL not to be playable.")
    expect(!ShuffleMusicTrack.isPlayableExternalRedirectURL(nil), "Expected nil URL not to be playable.")
}

testNextTrackRefillsAndAvoidsExcludedFirstTrack()
testPreviousTrackReturnsHistoryAndQueuesCurrentTrack()
testHistoryLimitKeepsMostRecentTracks()
testRemoveFromUpcomingPreventsDuplicateManualSelection()
testMergingMetadataDoesNotReplaceExistingTitleWithEmptyDetailTitle()
testMergingMetadataUsesNonEmptyDetailTitle()
testPreferredHTTPSPlaybackURLOnlyChangesNetEaseAudioHost()
testPlayableExternalRedirectURLRequiresNetEaseAudioHost()

print("ShuffleMusicCoreTests passed")
