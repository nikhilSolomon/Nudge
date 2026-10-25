import Foundation

struct SupabaseSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String

    var isExpiringSoon: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

struct SupabaseError: LocalizedError {
    let message: String
    let status: Int
    var errorDescription: String? { message }
}

/// Thin client for Supabase Auth (GoTrue) and PostgREST. No SDK; just URLSession.
final class SupabaseClient {
    let baseURL: URL
    let anonKey: String
    private(set) var session: SupabaseSession?
    private let sessionKey = "supabase.session"

    init?(urlString: String, anonKey: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host != nil, !anonKey.isEmpty else { return nil }
        self.baseURL = url
        self.anonKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = Keychain.load(key: sessionKey),
           let saved = try? JSONDecoder.supabase.decode(SupabaseSession.self, from: data),
           saved.userID.isEmpty == false {
            session = saved
        }
    }

    var isSignedIn: Bool { session != nil }

    // MARK: Auth

    func signUp(email: String, password: String) async throws -> SupabaseSession? {
        let data = try await send(path: "auth/v1/signup", method: "POST",
                                  body: ["email": email, "password": password], authenticated: false)
        if let s = Self.parseSession(data) {
            store(s)
            return s
        }
        return nil // email confirmation required; no session yet
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let data = try await send(path: "auth/v1/token", method: "POST", query: ["grant_type": "password"],
                                  body: ["email": email, "password": password], authenticated: false)
        guard let s = Self.parseSession(data) else {
            throw SupabaseError(message: "Sign-in response had no session.", status: 200)
        }
        store(s)
        return s
    }

    func signOut() {
        if let s = session {
            Task { _ = try? await send(path: "auth/v1/logout", method: "POST", authenticated: true, bearer: s.accessToken) }
        }
        session = nil
        Keychain.delete(key: sessionKey)
    }

    func refreshIfNeeded() async throws {
        guard let s = session, s.isExpiringSoon else { return }
        let data = try await send(path: "auth/v1/token", method: "POST", query: ["grant_type": "refresh_token"],
                                  body: ["refresh_token": s.refreshToken], authenticated: false)
        guard let fresh = Self.parseSession(data) else {
            throw SupabaseError(message: "Could not refresh session.", status: 401)
        }
        store(fresh)
    }

    private func store(_ s: SupabaseSession) {
        session = s
        if let data = try? JSONEncoder.supabase.encode(s) {
            Keychain.save(data, key: sessionKey)
        }
    }

    private static func parseSession(_ data: Data) -> SupabaseSession? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String else { return nil }
        let user = obj["user"] as? [String: Any]
        let expiresAt: Date
        if let at = obj["expires_at"] as? TimeInterval {
            expiresAt = Date(timeIntervalSince1970: at)
        } else if let secs = obj["expires_in"] as? TimeInterval {
            expiresAt = Date().addingTimeInterval(secs)
        } else {
            expiresAt = Date().addingTimeInterval(3600)
        }
        return SupabaseSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt,
                               userID: user?["id"] as? String ?? "", email: user?["email"] as? String ?? "")
    }

    // MARK: PostgREST

    func select(table: String, query: [String: String]) async throws -> Data {
        try await refreshIfNeeded()
        var q = query
        q["select"] = q["select"] ?? "*"
        return try await send(path: "rest/v1/\(table)", method: "GET", query: q, authenticated: true)
    }

    func upsert(table: String, rows: [[String: Any]], conflictColumn: String = "id") async throws {
        guard !rows.isEmpty else { return }
        try await refreshIfNeeded()
        _ = try await send(path: "rest/v1/\(table)", method: "POST", query: ["on_conflict": conflictColumn],
                           jsonBody: rows, authenticated: true,
                           headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }

    // MARK: Transport

    private func send(path: String, method: String, query: [String: String] = [:],
                      body: [String: Any]? = nil, jsonBody: Any? = nil,
                      authenticated: Bool, bearer: String? = nil,
                      headers: [String: String] = [:]) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = bearer ?? (authenticated ? session?.accessToken : nil) ?? anonKey
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        if let jsonBody { req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody) }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw SupabaseError(message: Self.errorMessage(from: data, status: status), status: status)
        }
        return data
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error_description", "msg", "message", "error", "hint", "details"] {
                if let v = obj[key] as? String, !v.isEmpty { return v }
            }
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty { return text }
        return "HTTP \(status)"
    }
}

// MARK: - Dates

extension JSONDecoder {
    static let supabase: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let supabase: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

enum PostgresDate {
    private static let formatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
         "yyyy-MM-dd'T'HH:mm:ss.SSSSSXXXXX",
         "yyyy-MM-dd'T'HH:mm:ss.SSSSXXXXX",
         "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
         "yyyy-MM-dd'T'HH:mm:ss.SSXXXXX",
         "yyyy-MM-dd'T'HH:mm:ss.SXXXXX",
         "yyyy-MM-dd'T'HH:mm:ssXXXXX"].map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = fmt
            return f
        }
    }()

    private static let output: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func string(_ d: Date) -> String { output.string(from: d) }
}
