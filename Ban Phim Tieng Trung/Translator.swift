//
//  Translator.swift
//  Ban Phim Tieng Trung
//

import Foundation

/// Đổi giọng văn câu tiếng Trung: lịch sự (您, 请…) hoặc thân mật (你).
enum ChineseRegister {
    private static let requestStarts = ["帮我", "帮忙", "给我", "告诉我", "等一下", "等等", "发给我", "发我", "过来", "进来", "稍等", "跟我", "带我", "让我"]

    static func apply(_ text: String, polite: Bool) -> String {
        polite ? makePolite(text) : makeCasual(text)
    }

    private static func makePolite(_ text: String) -> String {
        let placeholder = "\u{1}"
        let withNin = text
            .replacingOccurrences(of: "你们", with: placeholder)
            .replacingOccurrences(of: "你", with: "您")
            .replacingOccurrences(of: placeholder, with: "你们")

        // Thêm 请 vào đầu các câu nhờ vả ("帮我…" → "请帮我…", "您帮我…" → "请您帮我…").
        return eachSentence(withNin) { sentence in
            let body = sentence.drop { $0.isWhitespace }
            let request = body.hasPrefix("您") ? body.dropFirst() : body
            let startsWithRequest = requestStarts.contains { request.hasPrefix($0) }
            let alreadyPolite = body.hasPrefix("请") || body.hasPrefix("麻烦")
            return startsWithRequest && !alreadyPolite ? "请" + body : String(body)
        }
    }

    private static func makeCasual(_ text: String) -> String {
        eachSentence(text.replacingOccurrences(of: "您", with: "你")) { sentence in
            let body = sentence.drop { $0.isWhitespace }
            if body.hasPrefix("请"), let next = body.dropFirst().first, !"问客假教".contains(next) {
                return String(body.dropFirst())
            }
            return String(body)
        }
    }

    private static func eachSentence(_ text: String, transform: (String) -> String) -> String {
        var result = ""
        var current = ""
        for char in text {
            current.append(char)
            if "。！？!?；;\n".contains(char) {
                result += transform(current)
                current = ""
            }
        }
        if !current.isEmpty { result += transform(current) }
        return result
    }
}

enum Translator {
    enum TranslatorError: LocalizedError {
        case http(status: Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case let .http(status): "máy chủ dịch trả lỗi \(status)"
            case .badResponse: "không đọc được kết quả dịch"
            }
        }
    }

    /// Endpoint dịch này không chính thức nên hay đổi tính nết: có lúc chặn theo client,
    /// có lúc chặn theo User-Agent. Thử lần lượt vài biến thể trước khi chịu thua.
    private static let clients = ["gtx", "dict-chrome-ex", "at"]

    static func translate(_ text: String, from source: String, to target: String) async throws -> String {
        var lastError: Error = TranslatorError.badResponse
        for client in clients {
            do {
                return try await request(text, from: source, to: target, client: client)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func request(_ text: String, from source: String, to target: String,
                                client: String) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: client),
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        // Thiếu User-Agent kiểu trình duyệt là hay bị trả 403.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw TranslatorError.http(status: status) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = json.first as? [Any]
        else { throw TranslatorError.badResponse }

        let translated = segments
            .compactMap { ($0 as? [Any])?.first as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else { throw TranslatorError.badResponse }
        return translated
    }
}
