import Foundation

/// Dev / prod API base URL — never hardcode production to localhost.
enum APIConfig {
    private static let overrideKey = "ARFoodAPIBaseURLOverride"

    /// Resolved base URL (no trailing slash). Nil if not configured.
    static var baseURL: URL? {
        if let override = UserDefaults.standard.string(forKey: overrideKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return normalize(override)
        }
        if let s = Bundle.main.object(forInfoDictionaryKey: "ARFoodAPIBaseURL") as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return normalize(trimmed)
            }
        }
        #if DEBUG
        // Local development default only — Release builds require Info.plist / override.
        return URL(string: "http://127.0.0.1:3000")
        #else
        return nil
        #endif
    }

    static var isConfigured: Bool { baseURL != nil }

    static func setOverride(_ string: String?) {
        if let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(string.trimmingCharacters(in: .whitespacesAndNewlines), forKey: overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: overrideKey)
        }
    }

    static var overrideString: String? {
        UserDefaults.standard.string(forKey: overrideKey)
    }

    static func url(path: String) -> URL? {
        guard let base = baseURL else { return nil }
        let p = path.hasPrefix("/") ? path : "/" + path
        return URL(string: p, relativeTo: base)?.absoluteURL
    }

    /// Capture QR target — prefers deployed HTTPS `/capture`, falls back to deep link.
    static var captureQRURL: URL {
        if let base = baseURL {
            return base.appendingPathComponent("capture")
        }
        return URL(string: "arfood://capture")!
    }

    private static func normalize(_ string: String) -> URL? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return URL(string: trimmed)
    }
}
