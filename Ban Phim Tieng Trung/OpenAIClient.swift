//
//  OpenAIClient.swift
//  Ban Phim Tieng Trung
//
//  Gọi OpenAI Responses API với Structured Outputs. Khoá API do người dùng nhập, lưu trong Keychain.
//

import Foundation
import Security

/// Tốc độ nói của AI ở chế độ nói trực tiếp.
enum RealtimeSpeed: String, CaseIterable, Identifiable {
    case normal, slow, slower, slowest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: "Bình thường"
        case .slow: "Chậm nhẹ"
        case .slower: "Chậm"
        case .slowest: "Rất chậm"
        }
    }

    /// Chỉ dùng bội của 1/8: những số này biểu diễn đúng trong nhị phân, nếu không
    /// JSON sẽ ra kiểu 0.90000000000000002 và máy chủ từ chối vì quá 16 chữ số thập phân.
    var value: Double {
        switch self {
        case .normal: 1
        case .slow: 0.875
        case .slower: 0.75
        case .slowest: 0.625
        }
    }
}

enum OpenAISettings {
    static let modelKey = "openAIModel"
    static let fastModelKey = "openAIFastModel"
    static let levelKey = "conversationLevel"
    static let defaultModel = "gpt-5.6-luna"
    /// Model cho bước trả lời nhanh (câu nói + nghĩa), nên chọn loại rẻ và nhanh nhất.
    static let defaultFastModel = "gpt-5.6-luna"
    static let suggestedModels = ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-6-astra"]
    static let voiceKey = "openAIVoice"
    static let defaultVoice = "coral"
    static let voices = ["coral", "nova", "shimmer", "sage", "ballad", "marin", "alloy", "verse", "ash", "echo", "fable", "onyx", "cedar"]
    /// Realtime chỉ nhận bấy nhiêu giọng — nova, fable, onyx chỉ dùng được cho giọng đọc.
    static let realtimeVoices = ["alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse", "marin", "cedar"]
    static let speechModel = "gpt-4o-mini-tts"
    static let realtimeModelKey = "openAIRealtimeModel"
    static let realtimeSpeedKey = "openAIRealtimeSpeed"
    static let defaultRealtimeModel = "gpt-realtime-2"

    /// Người mới học nghe không kịp tốc độ thường, nên mặc định chậm sẵn.
    static var realtimeSpeed: RealtimeSpeed {
        RealtimeSpeed(rawValue: UserDefaults.standard.string(forKey: realtimeSpeedKey) ?? "") ?? .slower
    }

    /// Model cho chế độ nói trực tiếp (giọng đi thẳng lên model, không qua bước chuyển chữ).
    static var realtimeModel: String {
        let stored = UserDefaults.standard.string(forKey: realtimeModelKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return stored.isEmpty ? defaultRealtimeModel : stored
    }

    static var voice: String {
        UserDefaults.standard.string(forKey: voiceKey) ?? defaultVoice
    }

    /// Giọng cho chế độ nói trực tiếp; giọng chỉ dành cho đọc văn bản thì lùi về mặc định.
    static var realtimeVoice: String {
        let current = voice
        return realtimeVoices.contains(current) ? current : defaultVoice
    }

    static func supportsRealtime(voice: String) -> Bool { realtimeVoices.contains(voice) }

    private static let keychainService = "hihi.banphimtrung.openai"
    private static let keychainAccount = "apiKey"

    static var model: String {
        let stored = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return stored.isEmpty ? defaultModel : stored
    }

    static var fastModel: String {
        let stored = UserDefaults.standard.string(forKey: fastModelKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return stored.isEmpty ? defaultFastModel : stored
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
            // Không lấy mp3: máy chủ phát câu nào ghi câu đó, phần đầu file có thể chỉ khai
            // độ dài của câu đầu, và AVAudioPlayer tin con số đó nên đọc tới dấu chấm là tắt.
            // PCM thô không có đầu file, tự bọc WAV với độ dài đúng bằng dữ liệu nhận được.
            "response_format": "pcm",
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
        return wav(fromPCM: data)
    }

    /// PCM của OpenAI: 24 kHz, 16-bit, một kênh, little-endian.
    private static func wav(fromPCM pcm: Data, sampleRate: UInt32 = 24_000) -> Data {
        // Lẻ một byte thì bỏ, không thì mẫu cuối lệch nửa và kêu "tách".
        let samples = pcm.prefix(pcm.count & ~1)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let size = UInt32(samples.count)

        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        header.append(contentsOf: Array("RIFF".utf8))
        append(36 + size)
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(channels)
        append(sampleRate)
        append(sampleRate * UInt32(blockAlign))
        append(blockAlign)
        append(bitsPerSample)
        header.append(contentsOf: Array("data".utf8))
        append(size)
        return header + samples
    }

    /// Gửi hội thoại và nhận về JSON đúng `schema`, giải mã thành `T`.
    static func respond<T: Decodable>(
        instructions: String,
        messages: [Message],
        schemaName: String,
        schema: [String: Any],
        as type: T.Type,
        model: String? = nil
    ) async throws -> T {
        guard let key = OpenAISettings.apiKey else { throw ClientError.missingKey }

        var input: [[String: Any]] = [["role": "system", "content": instructions]]
        input += messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": model ?? OpenAISettings.model,
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
