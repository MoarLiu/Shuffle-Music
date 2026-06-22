import Foundation

public struct ShuffleMusicTrack: Equatable, Hashable, Identifiable {
    public let id: Int
    public let title: String
    public let artistNames: [String]
    public let albumTitle: String?
    public let coverImageURL: URL?
    public let sourceTitle: String?

    public init(
        id: Int,
        title: String,
        artistNames: [String] = [],
        albumTitle: String? = nil,
        coverImageURL: URL? = nil,
        sourceTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artistNames = artistNames
        self.albumTitle = albumTitle
        self.coverImageURL = coverImageURL
        self.sourceTitle = sourceTitle
    }

    public var externalPlaybackURL: URL {
        Self.externalPlaybackURL(forSongID: id)
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "曲目 \(id)" : trimmed
    }

    public var displayArtist: String {
        let artists = artistNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !artists.isEmpty {
            return artists.joined(separator: "、")
        }
        if let sourceTitle, !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourceTitle
        }
        return "未知歌手"
    }

    public func mergingMetadata(from detail: ShuffleMusicTrack) -> ShuffleMusicTrack {
        let detailTitle = detail.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ShuffleMusicTrack(
            id: id,
            title: detailTitle.isEmpty ? title : detailTitle,
            artistNames: detail.artistNames.isEmpty ? artistNames : detail.artistNames,
            albumTitle: detail.albumTitle ?? albumTitle,
            coverImageURL: detail.coverImageURL ?? coverImageURL,
            sourceTitle: sourceTitle ?? detail.sourceTitle
        )
    }

    public static func externalPlaybackURL(forSongID id: Int) -> URL {
        URL(string: "https://music.163.com/song/media/outer/url?id=\(id)")!
    }

    public static func preferredHTTPSPlaybackURL(from url: URL) -> URL {
        guard
            url.scheme == "http",
            let host = url.host,
            host == "music.126.net" || host.hasSuffix(".music.126.net"),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
    }

    public static func isPlayableExternalRedirectURL(_ url: URL?) -> Bool {
        guard
            let url,
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host?.lowercased(),
            host == "music.126.net" || host.hasSuffix(".music.126.net")
        else {
            return false
        }
        return true
    }
}
