//
//  WebBackend.swift
//  Tài khoản website tiengtrung.tuantu.com.vn: đăng nhập Google ngay trong app rồi dùng chung
//  hội thoại AI với trang học trên web. AI do máy chủ gọi (khoá OpenAI của máy chủ), nên người
//  dùng đã đăng nhập không cần nhập khoá OpenAI riêng.
//
//  Đăng nhập Google không cần SDK: ASWebAuthenticationSession + OAuth 2.0 PKCE lấy ID token,
//  gửi lên api/auth.php để đổi lấy token của máy chủ, giữ trong Keychain.
//

import AuthenticationServices
import CryptoKit
import SwiftUI
import UIKit

enum WebBackend {
    static let baseURL = URL(string: "https://tiengtrung.tuantu.com.vn")!

    /// Client ID loại iOS tạo ở Google Cloud Console (khoá GoogleIOSClientID trong Info.plist).
    static var googleClientID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "GoogleIOSClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.hasSuffix(".apps.googleusercontent.com") ? value : nil
    }

    /// Chỉ bản Debug: khoá đăng nhập giả lập (DEV_LOGIN_SECRET trong Config/DevLogin.local.xcconfig,
    /// phải trùng .env của website). Bản Release luôn trả nil.
    static var devLoginSecret: String? {
        #if DEBUG
        let value = (Bundle.main.object(forInfoDictionaryKey: "DevLoginSecret") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.count >= 32 && !value.hasPrefix("$(") ? value : nil
        #else
        return nil
        #endif
    }
}

struct WebBackendError: LocalizedError {
    let message: String
    /// Máy chủ báo token hết hạn / tài khoản bị khoá: phải đăng nhập lại.
    var needsLogin = false

    var errorDescription: String? { message }
}

struct WebUser: Codable, Equatable {
    let id: Int
    let email: String
    var username: String? = nil
    let name: String
    let avatar: String?
}

// MARK: - Tài khoản

final class WebAccountStore: NSObject, ObservableObject {
    static let shared = WebAccountStore()

    @Published private(set) var user: WebUser?
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?

    var isSignedIn: Bool { user != nil && token != nil }
    private(set) var token: String?

    private static let keychainService = "hihi.banphimtrung.web"
    private static let tokenAccount = "apiToken"
    private static let userKey = "webAccountUser"

    /// Giữ phiên đăng nhập Google đang mở, nếu không nó bị giải phóng giữa chừng.
    private var authSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
        token = Self.loadToken()
        user = UserDefaults.standard.data(forKey: Self.userKey).flatMap { try? JSONDecoder().decode(WebUser.self, from: $0) }
        if token == nil { user = nil }
    }

    func signInWithGoogle() {
        guard !isSigningIn else { return }
        guard let clientID = WebBackend.googleClientID else {
            // Chưa có client ID Google: bản Debug đăng nhập giả lập tài khoản dev (ID = 1).
            if let secret = WebBackend.devLoginSecret {
                signInDev(secret: secret)
            } else {
                errorMessage = "App chưa được cấu hình đăng nhập Google (thiếu GoogleIOSClientID trong Info.plist)."
            }
            return
        }
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                let idToken = try await googleIDToken(clientID: clientID)
                let (token, user) = try await Self.exchange(idToken: idToken)
                await MainActor.run { self.save(token: token, user: user) }
            } catch {
                await MainActor.run {
                    self.isSigningIn = false
                    // Bấm huỷ trong trang Google thì không phải lỗi.
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Đăng nhập bằng tên đăng nhập + mật khẩu (tài khoản dùng chung với website).
    func signIn(username: String, password: String) {
        passwordAuth(["action": "login", "username": username, "password": password])
    }

    /// Tạo tài khoản mới rồi đăng nhập luôn.
    func register(username: String, password: String, name: String) {
        passwordAuth(["action": "register", "username": username, "password": password, "name": name])
    }

    private func passwordAuth(_ payload: [String: String]) {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                let (token, user) = try await Self.authRequest(payload)
                await MainActor.run { self.save(token: token, user: user) }
            } catch {
                await MainActor.run {
                    self.isSigningIn = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func clearError() { errorMessage = nil }

    private func signInDev(secret: String) {
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                let (token, user) = try await Self.authRequest(["action": "dev", "secret": secret])
                await MainActor.run { self.save(token: token, user: user) }
            } catch {
                await MainActor.run {
                    self.isSigningIn = false
                    self.errorMessage = "Đăng nhập giả lập: \(error.localizedDescription)"
                }
            }
        }
    }

    func signOut() {
        if let token {
            // Thu hồi token trên máy chủ; mất mạng thì thôi, token tự hết hạn.
            var request = URLRequest(url: WebBackend.baseURL.appendingPathComponent("api/auth.php"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "logout"])
            URLSession.shared.dataTask(with: request).resume()
        }
        clear()
    }

    /// Máy chủ báo token không còn dùng được.
    func sessionExpired() {
        DispatchQueue.main.async {
            self.clear()
            self.errorMessage = "Phiên đăng nhập website đã hết. Hãy đăng nhập Google lại."
        }
    }

    private func save(token: String, user: WebUser) {
        Self.storeToken(token)
        UserDefaults.standard.set(try? JSONEncoder().encode(user), forKey: Self.userKey)
        self.token = token
        self.user = user
        isSigningIn = false
    }

    private func clear() {
        Self.storeToken(nil)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        token = nil
        user = nil
    }

    // MARK: Google OAuth (PKCE)

    private func googleIDToken(clientID: String) async throws -> String {
        let verifier = Self.base64URL(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = UUID().uuidString
        // Client iOS của Google nhận redirect theo scheme đảo ngược của client ID.
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirectURI = "\(scheme):/oauth2redirect"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: scheme) { url, error in
                    if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: error ?? WebBackendError(message: "Đăng nhập Google không thành công."))
                    }
                }
                session.presentationContextProvider = self
                self.authSession = session
                if !session.start() {
                    continuation.resume(throwing: WebBackendError(message: "Không mở được trang đăng nhập Google."))
                }
            }
        }
        authSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value
        else {
            throw WebBackendError(message: "Google không trả về mã đăng nhập. Hãy thử lại.")
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "code", value: code),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code_verifier", value: verifier),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String
        else {
            throw WebBackendError(message: "Không lấy được thông tin đăng nhập từ Google.")
        }
        return idToken
    }

    private static func exchange(idToken: String) async throws -> (String, WebUser) {
        try await authRequest(["action": "google", "idToken": idToken])
    }

    private static func authRequest(_ payload: [String: String]) async throws -> (String, WebUser) {
        struct Response: Decodable {
            let ok: Bool
            let token: String?
            let user: WebUser?
            let error: String?
        }
        var request = URLRequest(url: WebBackend.baseURL.appendingPathComponent("api/auth.php"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = payload
        body["device"] = await MainActor.run { UIDevice.current.model }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw WebBackendError(message: "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.")
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw WebBackendError(message: "Máy chủ trả về dữ liệu lỗi. Hãy thử lại sau.")
        }
        guard response.ok, let token = response.token, let user = response.user else {
            throw WebBackendError(message: response.error ?? "Đăng nhập không thành công.")
        }
        return (token, user)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: Keychain

    private static func storeToken(_ token: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
        guard let token else { return }
        var attributes = query
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension WebAccountStore: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - API hội thoại (api/conversation.php, giống hoc.php trên web)

enum WebConversationAPI {
    struct Word: Codable, Hashable {
        let zh: String
        let py: String
    }

    struct Line: Codable, Hashable {
        let zh: String
        let vi: String?
        let words: [Word]?

        var chatLine: ChatLine { WebConversationAPI.chatLine(zh: zh, vi: vi ?? "", words: words) }
    }

    struct Conversation: Codable, Identifiable, Hashable {
        static func == (a: Conversation, b: Conversation) -> Bool { a.id == b.id && a.userTurns == b.userTurns && a.title == b.title }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }

        let id: Int
        let title: String
        let emoji: String
        let caption: String
        let partnerRole: String
        let userRole: String
        let level: String
        let userTurns: Int
        let target: Int
        let updatedAt: String

        var scenario: Scenario {
            // id dương = hội thoại trên máy chủ (tình huống chỉ lưu trên máy có id âm).
            Scenario(id: id, topic: "Tự chọn", title: title, partnerRole: partnerRole,
                     partnerEmoji: emoji, userRole: userRole)
        }
    }

    struct Message: Codable {
        let id: Int
        let speaker: String
        let zh: String
        let vi: String
        let words: [Word]?
        let askedInVietnamese: Bool
        let feedback: String?
        let corrected: Line?
        let hints: [Line]?
        /// Chấm phát âm của câu người học (giống badge 🎯 / ⚡ trên web).
        let speech: Speech?

        var isUser: Bool { speaker == "user" }
        var hasWords: Bool { !(words ?? []).isEmpty }
        var chatLine: ChatLine { WebConversationAPI.chatLine(zh: zh, vi: vi, words: words) }
    }

    /// Kết quả chấm câu nói: % đúng (sau bước 2), tốc độ chữ/phút (chỉ khi nói bằng micro).
    struct Speech: Codable, Hashable {
        let input: String?
        let cpm: Int?
        let accuracy: Double?
        let wrongChars: Int?
    }

    /// Cách người học nhập câu, gửi kèm `send` để máy chủ phân tích phát âm / tốc độ nói.
    struct SpeechMeta: Codable, Hashable {
        /// "voice" hoặc "typed".
        var input: String
        /// "mic" hoặc "handsfree" (chỉ khi nói).
        var mode: String?
        var durationMs: Int?
        var confidence: Double?

        var payload: [String: Any] {
            var body: [String: Any] = ["input": input]
            if let mode { body["mode"] = mode }
            if let durationMs { body["durationMs"] = durationMs }
            if let confidence { body["confidence"] = confidence }
            return body
        }
    }

    struct WeekDay: Codable, Hashable {
        let label: String
        let done: Bool
        let today: Bool
        let future: Bool
    }

    struct Stats: Codable, Equatable {
        let streak: Int
        let todaySentences: Int
        let todayClean: Int?
        let totalSentences: Int
        let week: [WeekDay]?

        /// Mục tiêu mỗi ngày, giống cột phải trên web (hoc.php).
        static let sentenceGoal = 20
        static let cleanGoal = 10
    }

    private struct Envelope: Decodable {
        let ok: Bool
        let error: String?
        let login: Bool?
        let conversation: Conversation?
        let conversations: [Conversation]?
        let messages: [Message]?
        let stats: Stats?
        let vi: String?
    }

    /// Máy chủ vừa trả về tình huống (sau mỗi câu gửi): màn hình cập nhật tiến độ x/50.
    static let conversationUpdated = Notification.Name("WebConversationUpdated")
    /// Số câu hôm nay đổi: màn danh sách tải lại thống kê.
    static let statsChanged = Notification.Name("WebConversationStatsChanged")

    /// Pinyin AI tách sẵn nếu khớp đúng câu, không thì tự chuyển trên máy như bước 1 của app.
    static func chatLine(zh: String, vi: String, words: [Word]?) -> ChatLine {
        let text = zh.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = words ?? []
        let joined = words.map(\.zh).joined().filter { !$0.isWhitespace }
        let pinyinWords: [PinyinWord]
        if !words.isEmpty, joined == text.filter({ !$0.isWhitespace }) {
            pinyinWords = words.map { PinyinWord(zh: $0.zh, py: $0.py, hv: ChineseText.hanViet(forWord: $0.zh, pinyin: $0.py)) }
        } else if ChineseText.containsHan(text) {
            pinyinWords = ChineseText.words(for: text)
        } else {
            pinyinWords = [PinyinWord(zh: text, py: "")]
        }
        let meaning = vi.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatLine(zh: text, vi: ChineseText.containsHan(meaning) ? "" : meaning, words: pinyinWords)
    }

    static func state() async throws -> (stats: Stats?, conversations: [Conversation]) {
        let envelope = try await call("state", method: "GET")
        return (envelope.stats, envelope.conversations ?? [])
    }

    static func messages(conversationID: Int) async throws -> (conversation: Conversation?, messages: [Message]) {
        let envelope = try await call("messages", ["id": conversationID], method: "GET")
        return (envelope.conversation, envelope.messages ?? [])
    }

    static func create(title: String, level: String) async throws -> (conversation: Conversation, messages: [Message]) {
        let envelope = try await call("create", ["title": title, "level": level])
        guard let conversation = envelope.conversation else { throw WebBackendError(message: "Máy chủ chưa tạo được tình huống.") }
        return (conversation, envelope.messages ?? [])
    }

    static func send(conversationID: Int, text: String, speech: SpeechMeta? = nil) async throws -> [Message] {
        var payload: [String: Any] = ["id": conversationID, "text": text]
        if let speech { payload["speech"] = speech.payload }
        let messages = try await call("send", payload).messages ?? []
        await MainActor.run { NotificationCenter.default.post(name: statsChanged, object: nil) }
        return messages
    }

    /// Nghĩa tiếng Việt của câu tiếng Trung đang gõ (xem trước dưới ô nhập, giống web).
    static func translate(text: String) async throws -> String {
        try await call("translate", ["text": text]).vi ?? ""
    }

    static func reply(conversationID: Int) async throws -> [Message] {
        try await call("reply", ["id": conversationID]).messages ?? []
    }

    static func restart(conversationID: Int) async throws -> [Message] {
        try await call("restart", ["id": conversationID]).messages ?? []
    }

    static func detail(conversationID: Int, messageID: Int) async throws -> [Message] {
        try await call("detail", ["id": conversationID, "messageId": messageID]).messages ?? []
    }

    static func coach(conversationID: Int, text: String) async throws -> [Message] {
        try await call("coach", ["id": conversationID, "text": text]).messages ?? []
    }

    static func delete(conversationID: Int) async throws {
        _ = try await call("delete", ["id": conversationID])
    }

    private static func call(_ action: String, _ payload: [String: Any] = [:], method: String = "POST") async throws -> Envelope {
        guard let token = WebAccountStore.shared.token else {
            throw WebBackendError(message: "Hãy đăng nhập Google để dùng hội thoại của website.", needsLogin: true)
        }
        let endpoint = WebBackend.baseURL.appendingPathComponent("api/conversation.php")
        var request: URLRequest
        if method == "GET" {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "action", value: action)]
                + payload.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
            request = URLRequest(url: components.url!)
        } else {
            request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body = payload
            body["action"] = action
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Hosting có thể bỏ mất header Authorization; máy chủ đọc thêm header này.
        request.setValue(token, forHTTPHeaderField: "X-Api-Token")
        // Mỗi lượt AI có thể mất 10–60 giây.
        request.timeoutInterval = 90

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw WebBackendError(message: "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.")
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw WebBackendError(message: "Máy chủ trả về dữ liệu lỗi. Hãy thử lại sau.")
        }
        if envelope.login == true {
            WebAccountStore.shared.sessionExpired()
            throw WebBackendError(message: envelope.error ?? "Phiên đăng nhập đã hết.", needsLogin: true)
        }
        guard envelope.ok else {
            throw WebBackendError(message: envelope.error ?? "Có lỗi xảy ra. Hãy thử lại.")
        }
        if let conversation = envelope.conversation {
            await MainActor.run { NotificationCenter.default.post(name: conversationUpdated, object: conversation) }
        }
        return envelope
    }
}

// MARK: - Giọng đọc của máy chủ (api/speech.php, giống nút Nghe trên web)

enum WebSpeechAPI {
    static func speech(text: String, languageCode: String) async throws -> Data {
        guard let token = WebAccountStore.shared.token else {
            throw WebBackendError(message: "Chưa đăng nhập website.", needsLogin: true)
        }
        var request = URLRequest(url: WebBackend.baseURL.appendingPathComponent("api/speech.php"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Api-Token")
        let lang = languageCode.lowercased().hasPrefix("vi") ? "vi" : "zh"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": String(text.prefix(300)), "lang": lang])
        let (data, response) = try await URLSession.shared.data(for: request)
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard (response as? HTTPURLResponse)?.statusCode == 200, type.contains("audio") else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw WebBackendError(message: message ?? "Không tạo được giọng đọc.")
        }
        return data
    }
}

// MARK: - Thẻ đăng nhập website (dùng ở màn Tài khoản và Hội thoại AI)

struct WebAccountSection: View {
    @ObservedObject private var web = WebAccountStore.shared

    var body: some View {
        Section {
            if let user = web.user {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name).font(.subheadline.weight(.semibold))
                        Text(user.email.isEmpty ? "@\(user.username ?? "")" : user.email).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Đăng xuất khỏi website", role: .destructive) { web.signOut() }
            } else {
                PasswordLoginForm()
                GoogleSignInButton()
            }
            if let error = web.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Website tiengtrung.tuantu.com.vn")
        } footer: {
            Text("Đăng nhập cùng tài khoản với trang học trên web để dùng chung tình huống và lời thoại Hội thoại AI. AI do máy chủ trả lời, không cần khoá OpenAI riêng.")
        }
    }
}

struct GoogleSignInButton: View {
    @ObservedObject private var web = WebAccountStore.shared

    var body: some View {
        Button {
            web.signInWithGoogle()
        } label: {
            HStack(spacing: 10) {
                if web.isSigningIn {
                    ProgressView()
                } else {
                    Text("G")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                }
                Text(web.isSigningIn ? "Đang đăng nhập…" : "Đăng nhập bằng Google")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(.separator)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(web.isSigningIn)
    }
}

// MARK: - Màn đăng nhập (hiện sau màn chào khi chưa đăng nhập website)

struct WebLoginView: View {
    /// Bấm "Để sau": vào app không đăng nhập (hội thoại AI khi đó cần khoá OpenAI riêng).
    var onSkip: () -> Void

    @ObservedObject private var web = WebAccountStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let benefits: [(icon: String, title: String, detail: String)] = [
        ("bubble.left.and.bubble.right.fill", "Hội thoại AI không cần khoá", "AI của máy chủ trả lời, bạn chỉ việc nói."),
        ("arrow.triangle.2.circlepath", "Dùng chung với website", "Tình huống và lời thoại đồng bộ với tiengtrung.tuantu.com.vn."),
        ("flame.fill", "Giữ tiến độ", "Đổi máy hay cài lại app vẫn học tiếp được."),
    ]

    var body: some View {
        ZStack {
            MascotMood.happy.background.ignoresSafeArea()
            RadialGradient(colors: [.white.opacity(0.22), .clear], center: .top, startRadius: 20, endRadius: 420)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 24)

                    MascotView(mood: .happy, size: 116)
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)

                    VStack(spacing: 8) {
                        Text("Chào mừng đến\nBàn Phím Trung")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("Đăng nhập hoặc tạo tài khoản để luyện nói tiếng Trung cùng AI.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .opacity(0.9)
                    }
                    .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(benefits, id: \.title) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(MascotMood.happy.background)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(MascotMood.happy.background.opacity(0.12)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline.weight(.semibold))
                                    Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.systemBackground)))
                    .offset(y: appeared ? 0 : 24)
                    .opacity(appeared ? 1 : 0)

                    VStack(spacing: 12) {
                        VStack(spacing: 14) {
                            PasswordLoginForm(compact: false)
                            HStack(spacing: 10) {
                                Rectangle().fill(Color(.separator)).frame(height: 1)
                                Text("hoặc").font(.footnote).foregroundStyle(.secondary)
                                Rectangle().fill(Color(.separator)).frame(height: 1)
                            }
                        }
                        .padding(18)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.systemBackground)))

                        Button {
                            web.signInWithGoogle()
                        } label: {
                            HStack(spacing: 12) {
                                if web.isSigningIn {
                                    ProgressView().tint(.primary)
                                } else {
                                    GoogleLogo().frame(width: 22, height: 22)
                                }
                                Text(web.isSigningIn ? "Đang đăng nhập…" : "Tiếp tục với Google")
                                    .font(.headline)
                                    .foregroundStyle(Color(.label))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemBackground)))
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                        }
                        .buttonStyle(.plain)
                        .disabled(web.isSigningIn)

                        if let error = web.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.22)))
                        }

                        Button("Để sau") { onSkip() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.vertical, 6)
                    }

                    Text("Tài khoản dùng chung với website. Mật khẩu được mã hoá một chiều trên máy chủ; với Google, app chỉ nhận tên, email và ảnh đại diện.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8)) { appeared = true }
        }
    }
}

/// Chữ G nhiều màu của Google, vẽ bằng SwiftUI (không cần ảnh).
struct GoogleLogo: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line = size * 0.2
            ZStack {
                arc(start: 0, end: 45, color: Color(red: 0.26, green: 0.52, blue: 0.96), line: line)
                arc(start: 45, end: 135, color: Color(red: 0.2, green: 0.66, blue: 0.33), line: line)
                arc(start: 135, end: 215, color: Color(red: 0.98, green: 0.74, blue: 0.02), line: line)
                arc(start: 215, end: 315, color: Color(red: 0.92, green: 0.26, blue: 0.21), line: line)
                Rectangle()
                    .fill(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .frame(width: size * 0.42, height: line)
                    .offset(x: size * 0.21)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    /// Cung tron tu goc start den end (do, 0 = ben phai, chieu kim dong ho).
    private func arc(start: Double, end: Double, color: Color, line: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: (end - start) / 360)
            .rotation(.degrees(start))
            .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .butt))
            .padding(line / 2)
    }
}

// MARK: - Đăng nhập / đăng ký bằng tên đăng nhập + mật khẩu

struct PasswordLoginForm: View {
    /// Nền tối (màn đăng nhập đỏ) thì chữ phụ màu trắng.
    var compact = true

    @ObservedObject private var web = WebAccountStore.shared
    @State private var registering = false
    @State private var name = ""
    @State private var username = ""
    @State private var password = ""
    @State private var localError: String?
    @FocusState private var focus: Field?

    private enum Field { case name, username, password }
    private let brandRed = Color(red: 0.86, green: 0.17, blue: 0.16)

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $registering.animation(.easeInOut(duration: 0.2))) {
                Text("Đăng nhập").tag(false)
                Text("Đăng ký").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: registering) { _ in
                localError = nil
                web.clearError()
            }

            if registering {
                field("Tên hiển thị (vd: Minh Anh)", text: $name, icon: "person")
                    .textContentType(.name)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .username }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            field("Tên đăng nhập", text: $username, icon: "at")
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .focused($focus, equals: .username)
                .submitLabel(.next)
                .onSubmit { focus = .password }

            HStack(spacing: 10) {
                Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 20)
                SecureField("Mật khẩu (ít nhất 8 ký tự)", text: $password)
                    .textContentType(registering ? .newPassword : .password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
            }
            .modifier(FieldBox())

            if let localError {
                Text(localError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if web.isSigningIn { ProgressView().tint(.white) }
                    Text(web.isSigningIn ? (registering ? "Đang tạo tài khoản…" : "Đang đăng nhập…")
                                         : (registering ? "Tạo tài khoản" : "Đăng nhập"))
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(brandRed))
            }
            .buttonStyle(.plain)
            .disabled(web.isSigningIn)
        }
        .padding(.vertical, compact ? 4 : 0)
    }

    private func field(_ placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            TextField(placeholder, text: text)
        }
        .modifier(FieldBox())
    }

    private func submit() {
        let user = username.trimmingCharacters(in: .whitespaces).lowercased()
        localError = nil
        guard user.range(of: "^[a-z0-9][a-z0-9_.]{2,31}$", options: .regularExpression) != nil else {
            localError = "Tên đăng nhập 3–32 ký tự, chỉ gồm chữ thường không dấu, số, dấu chấm hoặc gạch dưới."
            return
        }
        guard password.count >= 8 else {
            localError = "Mật khẩu cần ít nhất 8 ký tự."
            return
        }
        focus = nil
        if registering {
            web.register(username: user, password: password, name: name.trimmingCharacters(in: .whitespaces))
        } else {
            web.signIn(username: user, password: password)
        }
    }
}

private struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}
