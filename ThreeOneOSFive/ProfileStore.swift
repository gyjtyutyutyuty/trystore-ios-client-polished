import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var bookmarks: [String: Data] = [:]
    private let defaultsKey = "jvztxnx.profile.bookmarks"

    init() {
        bookmarks = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }

    func link(profileID: String, url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarks[profileID] = data
            persist()
        } catch {
            logStore("bookmark failed: \(error.localizedDescription)")
        }
    }

    func isLinked(profileID: String) -> Bool {
        guard let data = bookmarks[profileID] else { return false }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return false }
        return !stale && url.isFileURL
    }

    func url(profileID: String) -> URL? {
        guard let data = bookmarks[profileID] else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale, url.isFileURL else {
            return nil
        }
        return url
    }

    private func persist() {
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }

    private func logStore(_ message: String) {
        print("[TryStore] \(message)")
    }
}
