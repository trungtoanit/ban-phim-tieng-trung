//
//  OpenAIClient.swift
//  Ban Phim Tieng Trung
//
//  Gọi OpenAI Responses API với Structured Outputs. Khoá API do người dùng nhập, lưu trong Keychain.
//

import Foundation
import Security

enum OpenAISettings {
    static let modelKey = "openAIModel"
    static let levelKey = "conversationLevel"
    static let defaultModel = "gpt-5.6-luna"
    static let suggestedModels = ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-6-astra"]
    static let voiceKey = "openAIVoice"
    static let defaultVoice = "coral"
    static let voices = ["coral", "nova", "shimmer", "sage", "ballad", "marin", "alloy", "verse", "ash", "echo", "fable", "onyx", "cedar"]
    static let speechModel = "gpt-4o-mini-tts"

    static var voice: String {
        UserDefaults.standard.string(forKey: voiceKey) ?? defaultVoice
    }

    private static let keychainService = "hihi.banphimtrung.openai"
    private static let keychainAccount = "apiKey"

    static var model: String {
        let stored = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return stored.isEmpty ? defaultModel : stored
    }

    static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    static var hasAPIKey: Bool { apiKey != nil }

    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool {
        deleteAPIKey()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum OpenAIClient {
    struct Message {
        enum Role: String { case user, assistant }
        let role: Role
        let content: String
    }

    enum ClientError: LocalizedError {
        case missingKey
        case http(status: Int, message: String)
        case refusal(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .missingKey:
                "Chưa có khoá OpenAI. Nhấn ⚙︎ để nhập khoá API."
            case let .http(status, message):
                switch status {
                case 401: "Khoá OpenAI không hợp lệ hoặc đã bị thu hồi. Hãy nhập khoá mới."
                case 429: "OpenAI báo hết hạn mức hoặc gửi quá nhanh (429). Kiểm tra số dư tài khoản rồi thử lại."
                case 404: "Không tìm thấy model “\(OpenAISettings.model)”. Hãy chọn model khác trong cài đặt."
                default: "OpenAI trả lỗi \(status): \(message)"
                }
            case let .refusal(message):
                "AI từ chối trả lời: \(message)"
            case .badResponse:
                "Không đọc được phản hồi từ OpenAI. Hãy thử lại."
            }
        }
    }

    /// Tạo giọng đọc tự nhiên (MP3) bằng OpenAI.
    static func speech(text: String, languageCode: String) async throws -> Data {
        guard let key = OpenAISettings.apiKey else { throw ClientError.missingKey }
        let instructions = languageCode.hasPrefix("zh")
            ? "Speak natural, warm, conversational Mandarin Chinese with a standard Mainland accent, like a friendly native speaker chatting. Pace slightly slower than normal with clear, accurate tones for a language learner."
            : "Speak natural, warm, gentle Vietnamese like a friendly native speaker, at a relaxed conversational pace."
        let body: [String: Any] = [
            "model": OpenAISettings.speechModel,
            "input": text,
            "voice": OpenAISettings.voice,
            "instructions": instructions,
            "response_format": "mp3",
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "Lỗi không xác định"
            throw ClientError.http(status: status, message: message)
        }
        return data
    }

    /// Gửi hội thoại và nhận về JSON đúng `schema`, giải mã thành `T`.
    static func respond<T: Decodable>(
        instructions: String,
        messages: [Message],
        schemaName: String,
        schema: [String: Any],
        as type: T.Type
    ) async throws -> T {
        guard let key = OpenAISettings.apiKey else { throw ClientError.missingKey }

        var input: [[String: Any]] = [["role": "system", "content": instructions]]
        input += messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": OpenAISettings.model,
            "input": input,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": schemaName,
                    "schema": schema,
                    "strict": true,
                ],
            ],
            "max_output_tokens": 4000,
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard status == 200 else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "Lỗi không xác định"
            throw ClientError.http(status: status, message: message)
        }

        // Lấy phần văn bản của mục "message" (bỏ qua các mục suy luận nếu có).
        let contents = (json?["output"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
        if let refusal = contents.first(where: { $0["type"] as? String == "refusal" })?["refusal"] as? String {
            throw ClientError.refusal(refusal)
        }
        guard let text = contents.first(where: { $0["type"] as? String == "output_text" })?["text"] as? String,
              let textData = text.data(using: .utf8)
        else { throw ClientError.badResponse }

        do {
            return try JSONDecoder().decode(T.self, from: textData)
        } catch {
            throw ClientError.badResponse
        }
    }
}
