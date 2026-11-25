import Foundation

// Sends one message to the Claude API and decodes the CheckResult.
// Plain URLSession (Apple's built-in networking), no extra libraries,
// which keeps the keyboard extension small.
enum ClaudeClient {
    static let model = "claude-haiku-5-5"   // try "claude-sonnet-5-5" to compare

    enum CheckError: LocalizedError {
        case noFullAccess
        case http(Int, String)
        case unexpected(String)

        var errorDescription: String? {
            switch self {
            case .noFullAccess:
                return "Turn on Allow Full Access: Settings › General › Keyboard › Keyboards › AccuracyKeyboard."
            case .http(let code, let body):
                return "API error \(code): \(body.prefix(200))"
            case .unexpected(let why):
                return why
            }
        }
    }

    // prompt.md is copied into the keyboard bundle, so it stays the one
    // source of truth for the prompt (shared with check.py).
    static let systemPrompt: String = {
        guard let url = Bundle.main.url(forResource: "prompt", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("prompt.md is missing from the Keyboard target. Check its Target Membership in Xcode.")
        }
        return text
    }()

    // The JSON schema the answer must follow. "Structured outputs" makes
    // the API guarantee the reply matches it, so decoding can't fail on
    // a stray sentence of chat.
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "verdict": ["type": "string", "enum": ["natural", "not_natural", "error"]],
            "corrected": ["type": "string"],
            "changes": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "from": ["type": "string"],
                        "to": ["type": "string"],
                        "reason": ["type": "string"],
                    ],
                    "required": ["from", "to", "reason"],
                    "additionalProperties": false,
                ],
            ],
            "native_version": ["type": "string"],
        ],
        "required": ["verdict", "corrected", "changes", "native_version"],
        "additionalProperties": false,
    ]

    static func check(_ message: String) async throws -> CheckResult {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(Secrets.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": systemPrompt,
            "messages": [["role": "user", "content": message]],
            "output_config": [
                // "medium": thinks longer only when something needs fixing.
                // Natural messages stay ~2s; fixes take ~2–5s. Tested: catches
                // more real mistakes than "low" (e.g. 谢谢你很多).
                "effort": "medium",
                "format": ["type": "json_schema", "schema": schema],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw CheckError.http(status, String(decoding: data, as: UTF8.self))
        }

        // The reply's `content` is a list of blocks. The JSON answer is in
        // the "text" block (there may also be a "thinking" block to skip).
        struct APIResponse: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
            let stop_reason: String?
        }
        let api = try JSONDecoder().decode(APIResponse.self, from: data)
        if api.stop_reason == "refusal" {
            throw CheckError.unexpected("The model declined to check this message.")
        }
        if api.stop_reason == "max_tokens" {
            throw CheckError.unexpected("The reply was cut off. Try a shorter message.")
        }
        guard let json = api.content.first(where: { $0.type == "text" })?.text else {
            throw CheckError.unexpected("No answer in the reply.")
        }
        return try JSONDecoder().decode(CheckResult.self, from: Data(json.utf8))
    }
}
