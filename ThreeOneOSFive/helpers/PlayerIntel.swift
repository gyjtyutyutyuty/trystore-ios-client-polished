import Foundation
import UIKit
import WebKit

// MARK: - Models

/// Equipment slots the profile page exposes. The order drives the badge
/// placement on the 3D stage and the sort order of the outfit list.
enum PlayerOutfitSlot: String, CaseIterable, Identifiable, Codable {
    case hair
    case face
    case mask
    case top
    case pants
    case shoes
    case pin
    case title
    case other

    var id: String { rawValue }

    var localizationKey: String { "intel.slot.\(rawValue)" }

    /// Badge anchor on the stage, as a fraction of the viewport. Values are
    /// hand-tuned against the bundled meshes: head high, feet low, and the
    /// sides alternate so a badge never covers the torso.
    var stageAnchor: CGPoint? {
        switch self {
        case .hair: return CGPoint(x: 0.24, y: 0.14)
        case .face: return CGPoint(x: 0.76, y: 0.20)
        case .mask: return CGPoint(x: 0.22, y: 0.31)
        case .top: return CGPoint(x: 0.78, y: 0.42)
        case .pants: return CGPoint(x: 0.22, y: 0.60)
        case .shoes: return CGPoint(x: 0.78, y: 0.80)
        case .pin, .title, .other: return nil
        }
    }
}

struct PlayerOutfitItem: Identifiable, Hashable, Codable {
    let name: String
    let slot: PlayerOutfitSlot
    let rarity: String
    let likes: Int
    let iconURL: URL?
    let pageURL: URL?
    let has3D: Bool

    var id: String {
        "\(slot.rawValue)|\(name.lowercased())|\(pageURL?.absoluteString ?? "")"
    }
}

struct PlayerIntelProfile: Identifiable, Hashable, Codable {
    let uid: String
    let nickname: String
    let region: String
    let level: Int
    let likes: Int
    let rank: String?
    let rankPoints: Int?
    let avatarURL: URL?
    let profileURL: URL?
    let updatedAt: String?

    var id: String { uid }
}

/// One row from the profile page's detail tables (account, indicators). The
/// label is already localised by the page, so it is shown verbatim.
struct PlayerStatLine: Identifiable, Codable, Hashable {
    let label: String
    let value: String

    var id: String { label }
}

/// One discipline's rank card: current standing plus its peak.
struct PlayerRankLine: Codable, Hashable {
    var rank: String = ""
    var points: String = ""
    var bestRank: String = ""
    var bestValue: String = ""
}

/// Everything the public profile page publishes about a player: level and
/// experience, likes, both rank ladders with their peaks, the special role, the
/// account table and the indicator table.
struct PlayerGameStats: Codable, Hashable {
    var level: String = ""
    var experience: String = ""
    var likes: String = ""
    var battleRoyale: PlayerRankLine?
    var clashSquad: PlayerRankLine?
    var role: String?
    var roleGroup: String?
    var account: [PlayerStatLine] = []
    var indicators: [PlayerStatLine] = []

    var isEmpty: Bool {
        level.isEmpty && experience.isEmpty && likes.isEmpty
            && battleRoyale == nil && clashSquad == nil
            && account.isEmpty && indicators.isEmpty
    }
}

/// One load of the player page: the equipped items and every stat block.
struct PlayerProfilePage {
    let items: [PlayerOutfitItem]
    let stats: PlayerGameStats
}

/// One row in the player roster. A row exists from the moment an ID is added,
/// so ten IDs can load independently and one failure never clears the rest.
struct PlayerIntelEntry: Identifiable, Codable, Equatable {
    let uid: String
    var profile: PlayerIntelProfile?
    var items: [PlayerOutfitItem]
    var stats: PlayerGameStats?
    var outfitFailed: Bool
    var errorKey: String?
    var isLoading: Bool

    var id: String { uid }
}

/// The roster survives launches. Cached garment files live in Caches and may
/// be evicted; the stage downloads them again when a player is selected.
enum PlayerRosterStore {
    private static let key = "player_intel_roster_v1"

    static func load() -> [PlayerIntelEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([PlayerIntelEntry].self, from: data)
        else {
            return []
        }
        return entries.map { entry in
            var restored = entry
            restored.isLoading = false
            return restored
        }
    }

    static func save(_ entries: [PlayerIntelEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum PlayerIntelError: Error {
    case invalidID
    case notFound
    case offline
    case service
    case outfitUnavailable

    /// Views localise; the service only reports which sentence applies.
    var messageKey: String {
        switch self {
        case .invalidID: return "intel.error_invalid"
        case .notFound: return "intel.error_not_found"
        case .outfitUnavailable: return "intel.error_outfit"
        case .offline, .service: return "intel.error_network"
        }
    }
}

// MARK: - Profile lookup

/// Credential-free profile lookup. Garena's own guest registration is closed,
/// so this fronts the public Free Fire Jornal preview API, which exposes the
/// same public profile data without an account.
actor PlayerIntelService {
    static let shared = PlayerIntelService()

    /// The relay boots one preview per UID. Three at a time keeps a ten-ID
    /// roster from tripping its rate limit while still filling quickly.
    private static let gate = AsyncGate(value: 3)

    private let baseURL = URL(string: "https://freefirejornal.com")!
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    private var headers: [String: String] {
        [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-FFJ-FF-Profile": "preview",
            "Origin": baseURL.absoluteString,
            "Referer": baseURL.absoluteString + "/en/free-fire-profile/",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
                + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        ]
    }

    func profile(uid rawUID: String, language: String) async throws -> PlayerIntelProfile {
        let uid = rawUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...20).contains(uid.count), uid.allSatisfy({ $0.isNumber }) else {
            throw PlayerIntelError.invalidID
        }

        await Self.gate.wait()
        defer { Task { await Self.gate.signal() } }

        let bootstrap: BootstrapResponse = try await post(
            "/api/freefire/profile-preview/bootstrap",
            body: ["id": uid, "languageCode": language]
        )
        guard let token = bootstrap.token, !token.isEmpty else {
            throw PlayerIntelError.invalidID
        }

        let deadline = Date().addingTimeInterval(90)
        var attempts = 0

        while Date() < deadline, attempts < 14, !Task.isCancelled {
            attempts += 1
            let (status, data) = try await postRaw(
                "/api/freefire/profile-preview",
                body: ["id": uid, "token": token, "languageCode": language]
            )
            let preview = try? JSONDecoder().decode(PreviewResponse.self, from: data)

            switch status {
            case 200:
                if let profile = preview?.profile(fallbackUID: uid) {
                    return profile
                }
                if preview?.state == "invalid" { throw PlayerIntelError.invalidID }
                if preview?.state == "not_found" { throw PlayerIntelError.notFound }
            case 400:
                throw PlayerIntelError.invalidID
            case 404:
                throw PlayerIntelError.notFound
            case 425:
                try await pause(seconds: preview?.retryAfter ?? 6)
                continue
            case 202:
                try await pause(seconds: 4)
                continue
            default:
                try await pause(seconds: 3)
                continue
            }

            try await pause(seconds: 3)
        }

        throw PlayerIntelError.service
    }

    private func post<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        let (status, data) = try await postRaw(path, body: body)
        guard status == 200 else {
            if status == 400 { throw PlayerIntelError.invalidID }
            if status == 404 { throw PlayerIntelError.notFound }
            throw PlayerIntelError.service
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PlayerIntelError.service
        }
    }

    private func postRaw(_ path: String, body: [String: String]) async throws -> (Int, Data) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PlayerIntelError.service
            }
            return (http.statusCode, data)
        } catch let error as PlayerIntelError {
            throw error
        } catch {
            throw PlayerIntelError.offline
        }
    }

    private func pause(seconds: Int) async throws {
        let clamped = min(max(seconds, 1), 20)
        try await Task.sleep(nanoseconds: UInt64(clamped) * 1_000_000_000)
    }

    private struct BootstrapResponse: Decodable {
        let token: String?
        let delay: Int?
    }

    private struct PreviewResponse: Decodable {
        let state: String?
        let nickname: String?
        let region: String?
        let level: Int?
        let likes: Int?
        let rank: String?
        let rankPoints: Int?
        let avatarUrl: String?
        let profileUrl: String?
        let updatedAt: String?
        let retryAfter: Int?
        let message: String?

        func profile(fallbackUID: String) -> PlayerIntelProfile? {
            guard let nickname, !nickname.isEmpty else { return nil }
            return PlayerIntelProfile(
                uid: fallbackUID,
                nickname: nickname,
                region: region ?? "",
                level: level ?? 0,
                likes: likes ?? 0,
                rank: rank,
                rankPoints: rankPoints,
                avatarURL: avatarUrl.flatMap(URL.init(string:)),
                profileURL: profileUrl.flatMap(URL.init(string:)),
                updatedAt: updatedAt
            )
        }
    }
}

// MARK: - Equipped items

/// The profile page is server-rendered and sits behind a browser check, so a
/// plain request cannot read it. A real `WKWebView` passes that check, and the
/// equipment cards are stable DOM nodes; this loads the page off-screen and
/// reads them once they render.
@MainActor
final class PlayerOutfitScraper {
    static let shared = PlayerOutfitScraper()

    /// Each scrape owns a web view. Two at a time keeps ten queued IDs from
    /// stacking ten pages on the main thread.
    private static let gate = AsyncGate(value: 2)

    /// Items and every stat block from one page load.
    func page(uid: String, timeout: TimeInterval = 45) async throws -> PlayerProfilePage {
        guard let url = URL(string: "https://freefirejornal.com/en/profile/\(uid)/") else {
            throw PlayerIntelError.invalidID
        }

        await Self.gate.wait()
        defer { Task { await Self.gate.signal() } }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        view.isUserInteractionEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        view.alpha = 0.02

        attach(view)
        defer { detach(view) }

        _ = view.load(URLRequest(url: url))
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline, !Task.isCancelled {
            try await Task.sleep(nanoseconds: 900_000_000)

            guard let payload = try? await view.evaluateJavaScript(Self.probeScript),
                  let text = payload as? String,
                  let data = text.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if (root["state"] as? String) == "ready" {
                let cards = root["cards"] as? [[String: Any]] ?? []
                return PlayerProfilePage(
                    items: Self.items(from: cards),
                    stats: Self.stats(from: root)
                )
            }
        }

        throw PlayerIntelError.outfitUnavailable
    }

    /// Items only, for callers that do not need the stat blocks.
    func outfit(uid: String, timeout: TimeInterval = 35) async throws -> [PlayerOutfitItem] {
        try await page(uid: uid, timeout: timeout).items
    }

    private func attach(_ view: WKWebView) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first else {
            return
        }
        window.addSubview(view)
    }

    private func detach(_ view: WKWebView) {
        view.stopLoading()
        view.removeFromSuperview()
    }

    /// Reads the whole profile in one probe: the two detail tables, the summary
    /// cards, both rank cards, the role panel and the equipped items. The page is
    /// rendered by the site itself, so the labels come back in English.
    private static let probeScript = """
    (function () {
      function clean(value) {
        return String(value || '').replace(/\\s+/g, ' ').trim();
      }

      function lines(el) {
        if (!el) { return []; }
        return (el.innerText || '').split('\\n')
          .map(function (line) { return line.trim(); })
          .filter(function (line) { return line.length > 0; });
      }

      var tables = Array.prototype.slice.call(document.querySelectorAll('dl.ffp-details-grid'));
      if (!tables.length) {
        return JSON.stringify({ state: 'waiting' });
      }

      var details = tables.map(function (dl) {
        var labels = Array.prototype.slice.call(dl.querySelectorAll('dt'));
        var values = Array.prototype.slice.call(dl.querySelectorAll('dd'));
        return labels.map(function (dt, index) {
          return {
            label: clean(dt.textContent),
            value: values[index] ? clean(values[index].textContent) : ''
          };
        });
      });

      var summary = {};
      Array.prototype.slice.call(document.querySelectorAll('.ffp-summary-card')).forEach(function (card) {
        var rows = lines(card);
        if (rows.length > 1) { summary[rows[0]] = rows.slice(1); }
      });

      var ranks = {};
      Array.prototype.slice.call(document.querySelectorAll('.ffp-rank-card')).forEach(function (card) {
        var rows = lines(card);
        if (rows.length > 1) { ranks[rows[0]] = rows.slice(1); }
      });

      var cards = Array.prototype.slice.call(document.querySelectorAll('.ffp-equipment-card')).map(function (card) {
        var image = card.querySelector('img');
        return {
          name: (card.getAttribute('title') || '').replace(/^View\\s+/i, ''),
          href: card.href || '',
          text: clean(card.innerText),
          icon: (image && image.src) || ''
        };
      });

      return JSON.stringify({
        state: 'ready',
        summary: summary,
        ranks: ranks,
        details: details,
        role: lines(document.querySelector('.ffp-role-panel .ffp-role-copy')),
        cards: cards
      });
    })()
    """

    /// The summary and rank cards are read positionally — label, then value —
    /// so the parse does not depend on which language the page rendered in.
    private static func stats(from root: [String: Any]) -> PlayerGameStats {
        var stats = PlayerGameStats()

        let summary = root["summary"] as? [String: [String]] ?? [:]
        let ranks = root["ranks"] as? [String: [String]] ?? [:]

        func card(_ table: [String: [String]], _ needle: String) -> [String]? {
            table.first { $0.key.uppercased().contains(needle) }?.value
        }

        if let level = card(summary, "LEVEL") {
            stats.level = level.first ?? ""
            stats.experience = level.count > 1 ? level[1] : ""
        }
        let likes = card(summary, "LIKE")
        stats.likes = likes?.first ?? ""
        stats.battleRoyale = rankLine(card(ranks, "BATTLE"))
        stats.clashSquad = rankLine(card(ranks, "CLASH"))

        let tables = root["details"] as? [[[String: String]]] ?? []
        let parsed = tables.map { rows in
            rows.compactMap { row -> PlayerStatLine? in
                let label = (row["label"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { return nil }
                return PlayerStatLine(label: label, value: row["value"] ?? "")
            }
        }
        stats.account = parsed.first ?? []
        stats.indicators = parsed.count > 1 ? parsed[1] : []

        if let role = root["role"] as? [String], role.count >= 2 {
            stats.role = role[1]
            stats.roleGroup = role.count > 2 ? role[2] : nil
        }

        return stats
    }

    /// `[rank, points, "Best rank", best, "Peak points", peak]`, in whichever
    /// language the page used.
    private static func rankLine(_ lines: [String]?) -> PlayerRankLine? {
        guard let lines, lines.count >= 2 else { return nil }
        var line = PlayerRankLine()
        line.rank = lines[0]
        line.points = lines[1]
        if lines.count >= 4 { line.bestRank = lines[3] }
        if lines.count >= 6 { line.bestValue = lines[5] }
        return line
    }

    private static func items(from cards: [[String: Any]]) -> [PlayerOutfitItem] {
        var seen = Set<String>()
        var result: [PlayerOutfitItem] = []

        for card in cards {
            let name = (card["name"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let href = card["href"] as? String ?? ""
            let text = card["text"] as? String ?? ""
            let icon = card["icon"] as? String ?? ""
            let slot = slot(for: name, href: href, text: text)

            guard seen.insert("\(slot.rawValue)|\(name.lowercased())").inserted else { continue }

            result.append(
                PlayerOutfitItem(
                    name: name,
                    slot: slot,
                    rarity: rarity(in: text),
                    likes: likes(in: text),
                    iconURL: URL(string: icon),
                    pageURL: URL(string: href),
                    has3D: text.hasPrefix("3D") || text.contains(" 3D ")
                )
            )
        }

        return result.sorted { lhs, rhs in
            let left = PlayerOutfitSlot.allCases.firstIndex(of: lhs.slot) ?? 99
            let right = PlayerOutfitSlot.allCases.firstIndex(of: rhs.slot) ?? 99
            if left != right { return left < right }
            return lhs.likes > rhs.likes
        }
    }

    private static func slot(for name: String, href: String, text: String) -> PlayerOutfitSlot {
        let slugTokens = Set(
            (URL(string: href)?.lastPathComponent ?? "")
                .lowercased()
                .split(separator: "-")
                .map(String.init)
        )

        func has(_ tokens: [String]) -> Bool {
            tokens.contains { slugTokens.contains($0) }
        }

        if has(["pin", "insignia", "insigne"]) { return .pin }
        if has(["title", "titulo", "titolo"]) { return .title }
        if has(["mask", "mascara", "maschera"]) { return .mask }
        if has(["pant", "pants", "calca", "trouser", "trousers"]) { return .pants }
        if has(["shoe", "shoes", "sneaker", "sneakers", "boot", "boots", "sapato", "sapatos", "tenis"]) {
            return .shoes
        }
        if has(["hair", "cabelo", "hairstyle"]) { return .hair }
        if has(["face", "paint", "pintura", "facepaint"]) { return .face }
        if has(["top", "shirt", "jacket", "hoodie", "dress", "camisa", "blusa"]) { return .top }

        let upper = text.uppercased()
        if upper.hasPrefix("PIN") { return .pin }
        if upper.hasPrefix("TITLE") { return .title }
        return .other
    }

    private static let rarityTokens = ["Artifact", "Legendary", "Epic+", "Epic", "Rare", "Uncommon", "Common"]

    private static func rarity(in text: String) -> String {
        rarityTokens.first { text.localizedCaseInsensitiveContains($0) } ?? ""
    }

    private static func likes(in text: String) -> Int {
        guard let heart = text.range(of: "\u{2665}") else { return 0 }
        let digits = text[heart.upperBound...].filter(\.isNumber)
        return Int(String(digits)) ?? 0
    }
}
