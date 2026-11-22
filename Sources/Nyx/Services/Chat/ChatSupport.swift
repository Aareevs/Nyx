import Foundation

/// The four services the island's chat can talk to. Each person brings their
/// own key; nothing here goes through any server of ours.
enum ChatProvider: String, CaseIterable, Identifiable, Codable {
    case claude, openai, gemini, nvidia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        case .nvidia: return "NVIDIA"
        }
    }

    /// A plain symbol. The services' own logos are theirs, so none ship here.
    var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .openai: return "circle.hexagongrid"
        case .gemini: return "diamond"
        case .nvidia: return "cpu"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-…"
        case .openai: return "sk-…"
        case .gemini: return "AIza…"
        case .nvidia: return "nvapi-…"
        }
    }

    /// Used only until the service's own model list has been read, or when it
    /// cannot be. The list is the source of truth.
    var fallbackModel: String {
        switch self {
        case .claude: return "claude-sonnet-5-5"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-2.5-flash"
        case .nvidia: return ChatAPI.nvidiaPreferred[0]
        }
    }

    var baseURL: URL {
        switch self {
        case .claude: return URL(string: "https://api.anthropic.com/v1")!
        case .openai: return URL(string: "https://api.openai.com/v1")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        case .nvidia: return URL(string: "https://integrate.api.nvidia.com/v1")!
        }
    }

    /// The key in what was pasted: the key itself, or a code snippet it comes in,
    /// like the Python, Node or shell examples some services show with the key
    /// already filled in. Nil when there is nothing that looks like a key.
    static func extractKey(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20_000 else { return nil }
        let quoted = trimmed.contains("\"") || trimmed.contains("'") || trimmed.contains("`")
        if !quoted, trimmed.count >= 12, trimmed.count <= 400,
           trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
            return trimmed
        }
        for pattern in [#"nvapi-[A-Za-z0-9_\-]{16,}"#, #"sk-ant-[A-Za-z0-9_\-]{16,}"#,
                        #"AIza[A-Za-z0-9_\-]{20,}"#, #"sk-[A-Za-z0-9_\-]{20,}"#] {
            if let match = trimmed.range(of: pattern, options: .regularExpression) { return String(trimmed[match]) }
        }
        return nil
    }

    static func looksLikeKey(_ text: String) -> Bool { extractKey(from: text) != nil }

    /// Code that sets up a service but has no key in it, such as a snippet that
    /// still says $NVIDIA_API_KEY where the key goes.
    static func isSnippetWithoutKey(_ text: String) -> Bool {
        guard extractKey(from: text) == nil else { return false }
        let lowered = text.lowercased()
        return text.contains("\n") && ["api_key", "apikey", "authorization", "bearer", "base_url", "baseurl"].contains { lowered.contains($0) }
    }
}

struct ChatModel: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var created: Date?

    init(id: String, name: String? = nil, created: Date? = nil) {
        self.id = id
        self.name = name ?? id
        self.created = created
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
    /// Text the person attached, such as a selection. Shown as a chip, and sent
    /// with the message.
    var context: String?
    /// The reply stopped before it was complete.
    var interrupted = false
    /// Files added to this message: their names stay in the saved chat.
    var files: [ChatFileInfo] = []
    /// The text read from those files, sent with the message.
    var fileText: String?
    /// Pictures from those files. Sent while the app runs, never saved.
    var images: [ChatImage] = []

    private enum CodingKeys: String, CodingKey {
        case id, role, text, context, interrupted, files, fileText
    }

    init(id: UUID = UUID(), role: Role, text: String, context: String? = nil, interrupted: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.context = context
        self.interrupted = interrupted
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try values.decode(Role.self, forKey: .role)
        text = try values.decode(String.self, forKey: .text)
        context = try values.decodeIfPresent(String.self, forKey: .context)
        interrupted = try values.decodeIfPresent(Bool.self, forKey: .interrupted) ?? false
        files = try values.decodeIfPresent([ChatFileInfo].self, forKey: .files) ?? []
        fileText = try values.decodeIfPresent(String.self, forKey: .fileText)
    }

    /// What the service is sent for this message.
    var requestText: String {
        var parts: [String] = []
        if let fileText, !fileText.isEmpty { parts.append(fileText) }
        if let context, !context.isEmpty { parts.append("Selected text:\n\"\"\"\n\(context)\n\"\"\"") }
        parts.append(text)
        return parts.joined(separator: "\n\n")
    }

    /// The files' text as one block, each under its name.
    static func fileBlock(_ files: [ChatPendingFile]) -> String? {
        let blocks = files.compactMap { file -> String? in
            guard let text = file.text else { return nil }
            return "Attached file \"\(file.name)\"\(file.truncated ? " (cut short)" : ""):\n\"\"\"\n\(text)\n\"\"\""
        }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n\n")
    }
}

struct ChatConversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var provider: ChatProvider
    var model: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 48 else { return trimmed }
        return String(trimmed.prefix(47)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// One thing a stream says.
enum ChatStreamEvent: Equatable {
    case text(String)
    case done
    case failed(String)
}

/// Why a reply did not arrive.
enum ChatFailure: Error, Equatable {
    case noKey
    case rejected
    case rateLimited
    case unreachable
    case emptyReply
    case api(String)
}

/// The requests the services want, and what they answer. Nothing here opens a
/// connection, so every shape can be checked without one.
enum ChatAPI {
    static let anthropicVersion = "2023-06-01"
    static let claudeMaxTokens = 8192

    // MARK: Requests

    static func chatRequest(provider: ChatProvider, model: String, apiKey: String,
                            system: String?, messages: [ChatMessage]) -> URLRequest {
        let sendable = messages.filter { !($0.role == .assistant && $0.text.isEmpty) }
        let system = system?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSystem = !(system ?? "").isEmpty
        var body: [String: Any]
        var request: URLRequest

        switch provider {
        case .claude:
            request = URLRequest(url: provider.baseURL.appendingPathComponent("messages"))
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
            body = ["model": model, "max_tokens": claudeMaxTokens, "stream": true,
                    "messages": sendable.map { ["role": $0.role.rawValue, "content": claudeContent($0)] as [String: Any] }]
            if hasSystem, let system { body["system"] = system }
        case .openai, .nvidia:
            request = URLRequest(url: provider.baseURL.appendingPathComponent("chat/completions"))
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            var list: [[String: Any]] = []
            if hasSystem, let system { list.append(["role": "system", "content": system]) }
            list += sendable.map { ["role": $0.role.rawValue, "content": openAIContent($0)] as [String: Any] }
            body = ["model": model, "stream": true, "messages": list]
        case .gemini:
            var components = URLComponents(
                url: provider.baseURL.appendingPathComponent("models/\(model):streamGenerateContent"),
                resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            request = URLRequest(url: components.url!)
            // The key goes in a header, never in the address, which logs keep.
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            body = ["contents": sendable.map {
                ["role": $0.role == .user ? "user" : "model", "parts": geminiParts($0)] as [String: Any]
            }]
            if hasSystem, let system { body["systemInstruction"] = ["parts": [["text": system]]] }
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// A message's content for Claude: plain text, or text with its pictures.
    private static func claudeContent(_ message: ChatMessage) -> Any {
        guard !message.images.isEmpty else { return message.requestText }
        return message.images.map { image -> [String: Any] in
            ["type": "image", "source": ["type": "base64", "media_type": image.mime, "data": image.base64]]
        } + [["type": "text", "text": message.requestText]]
    }

    private static func openAIContent(_ message: ChatMessage) -> Any {
        guard !message.images.isEmpty else { return message.requestText }
        return [["type": "text", "text": message.requestText] as [String: Any]] + message.images.map { image -> [String: Any] in
            ["type": "image_url", "image_url": ["url": "data:\(image.mime);base64,\(image.base64)"]]
        }
    }

    private static func geminiParts(_ message: ChatMessage) -> [[String: Any]] {
        message.images.map { ["inline_data": ["mime_type": $0.mime, "data": $0.base64]] as [String: Any] }
            + [["text": message.requestText]]
    }

    static func modelsRequest(provider: ChatProvider, apiKey: String) -> URLRequest {
        var url = provider.baseURL.appendingPathComponent("models")
        if provider == .claude || provider == .gemini {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: provider == .claude ? "limit" : "pageSize", value: "1000")]
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        switch provider {
        case .claude:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        case .gemini:
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .openai, .nvidia:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// Models that answer for an ordinary account, newest first. The ones the
    /// service lists lead; these only say which of them to try first.
    static let nvidiaPreferred = ["nvidia/nemotron-3.5-lightning-30b-a3b", "nvidia/nemotron-3.5-bolt-e4b",
                                  "mistralai/mistral-large-4-1t-a52b", "nvidia/nemotron-3-super-120b-a12b",
                                  "openai/gpt-oss-20b", "google/gemma-4-31b-it", "poolside/laguna-xs-2.1",
                                  "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning", "nvidia/nemotron-3-ultra-550b-a55b"]

    /// One word asked of a model, to prove a key and the model together.
    static func probeRequest(provider: ChatProvider, model: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: provider.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model, "max_tokens": 1, "stream": false,
            "messages": [["role": "user", "content": "Hi"]]])
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// Every listed model, the preferred ones first, in the order they are offered.
    static func probeCandidates(from models: [ChatModel], limit: Int = 60) -> [String] {
        let ids = models.map(\.id)
        var order = nvidiaPreferred.filter(ids.contains)
        for id in ids where !order.contains(id) { order.append(id) }
        return Array(order.prefix(limit))
    }

    // MARK: Models

    private static let notForChat = ["audio", "realtime", "transcribe", "tts", "image", "embedding", "embed",
                                     "moderation", "whisper", "dall-e", "davinci", "babbage", "search",
                                     "instruct", "computer-use", "aqa", "imagen", "veo", "live", "robotics"]

    static func parseModels(_ data: Data, provider: ChatProvider) -> [ChatModel] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        switch provider {
        case .claude:
            let rows = root["data"] as? [[String: Any]] ?? []
            return rows.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                return ChatModel(id: id, name: row["display_name"] as? String,
                                 created: (row["created_at"] as? String).flatMap(parseDate))
            }
        case .openai, .nvidia:
            let rows = root["data"] as? [[String: Any]] ?? []
            let models: [ChatModel] = rows.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                let created = (row["created"] as? Double).map { Date(timeIntervalSince1970: $0) }
                return ChatModel(id: id, created: created)
            }
            if provider == .nvidia {
                // The catalog also holds embedding, ranking, speech, image and
                // safety models, which cannot chat. Chat-tuned models lead.
                let unfit = ["embed", "rerank", "reward", "guard", "safety", "parse", "clip", "retriev", "ocr", "asr",
                             "tts", "speech", "whisper", "diffusion", "flux", "sdxl", "stable-", "image", "segment",
                             "paddle", "gliner", "pii", "topic-control", "nemoguard", "translate", "riva"]
                let chatTuned = ["instruct", "chat", "nemotron", "-r1", "-it", "qwen", "llama", "mistral", "gemma", "deepseek"]
                let usable = models.filter { model in !unfit.contains { model.id.lowercased().contains($0) } }
                return usable.sorted { lhs, rhs in
                    func rank(_ id: String) -> Int { chatTuned.contains { id.lowercased().contains($0) } ? 0 : 1 }
                    return (rank(lhs.id), lhs.id) < (rank(rhs.id), rhs.id)
                }
            }
            let chat = models.filter { model in
                let id = model.id.lowercased()
                let family = id.hasPrefix("gpt-") || id.hasPrefix("chatgpt") || id.range(of: #"^o\d"#, options: .regularExpression) != nil
                return family && !notForChat.contains { id.contains($0) }
            }
            return chat.sorted { ($0.created ?? .distantPast, $0.id) > ($1.created ?? .distantPast, $1.id) }
        case .gemini:
            let rows = root["models"] as? [[String: Any]] ?? []
            let models: [ChatModel] = rows.compactMap { row in
                guard let name = row["name"] as? String,
                      let methods = row["supportedGenerationMethods"] as? [String],
                      methods.contains("generateContent") else { return nil }
                let id = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
                guard id.lowercased().hasPrefix("gemini"), !notForChat.contains(where: { id.lowercased().contains($0) })
                else { return nil }
                return ChatModel(id: id, name: row["displayName"] as? String)
            }
            return models.sorted { $0.id > $1.id }
        }
    }

    /// The model to start on when the person has not picked one: a mainstream
    /// model from the newest family, not a preview, a miniature or a variant.
    static func defaultModel(in models: [ChatModel], provider: ChatProvider) -> String {
        // Whole words of the name, so "gemini" is not taken for "mini".
        func plain(_ id: String, avoiding words: [String]) -> Bool {
            let id = id.lowercased()
            let parts = Set(id.split(separator: "-").map(String.init))
            return parts.isDisjoint(with: words) && id.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil
        }
        let variants = ["mini", "nano", "lite", "pro", "preview", "exp", "codex", "thinking", "vision", "turbo", "chat", "latest"]
        switch provider {
        case .claude:
            return models.first { $0.id.contains("sonnet") }?.id ?? models.first?.id ?? provider.fallbackModel
        case .openai:
            return models.first { plain($0.id, avoiding: variants) && $0.id.lowercased().hasPrefix("gpt-") }?.id
                ?? models.first?.id ?? provider.fallbackModel
        case .gemini:
            return models.first { $0.id.contains("flash") && plain($0.id, avoiding: variants) }?.id
                ?? models.first?.id ?? provider.fallbackModel
        case .nvidia:
            return nvidiaPreferred.first { preferred in models.contains { $0.id == preferred } }
                ?? models.first?.id ?? provider.fallbackModel
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    // MARK: Streams

    /// What one line of a stream says. Lines that carry nothing a person reads,
    /// like event names and keep-alives, answer nil.
    static func event(fromLine line: String, provider: ChatProvider) -> ChatStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let failure = errorMessage(in: json) { return .failed(failure) }

        switch provider {
        case .claude:
            switch json["type"] as? String {
            case "content_block_delta":
                guard let delta = json["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String, !text.isEmpty else { return nil }
                return .text(text)
            case "message_stop": return .done
            default: return nil
            }
        case .openai, .nvidia:
            guard let choice = (json["choices"] as? [[String: Any]])?.first,
                  let delta = choice["delta"] as? [String: Any],
                  let text = delta["content"] as? String, !text.isEmpty else { return nil }
            return .text(text)
        case .gemini:
            if let feedback = json["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
                return .failed("Blocked: \(reason)")
            }
            guard let candidate = (json["candidates"] as? [[String: Any]])?.first else { return nil }
            let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            // A thinking model sends its reasoning as parts flagged "thought".
            let text = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return .text(text) }
            if let reason = candidate["finishReason"] as? String,
               ["SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII"].contains(reason) {
                return .failed("Blocked: \(reason)")
            }
            return nil
        }
    }

    /// The service's own words for what went wrong, from a stream line or a
    /// failed response's body.
    static func errorMessage(in json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any] {
            return (error["message"] as? String) ?? (error["status"] as? String) ?? "Unknown error"
        }
        if let error = json["error"] as? String { return error }
        // NVIDIA answers in the problem-details shape: {"title": "Gone", "detail": "..."}.
        if let detail = json["detail"] as? String, !detail.isEmpty { return detail }
        if json["type"] as? String == "error", let message = json["message"] as? String { return message }
        return nil
    }

    static func failureMessage(body: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        return errorMessage(in: json)
    }

    /// How a refused request reads to the person.
    static func failure(status: Int, message: String?) -> ChatFailure {
        let lowered = (message ?? "").lowercased()
        let aboutTheKey = ["api key not valid", "invalid api key", "incorrect api key", "invalid x-api-key",
                           "authorization failed", "authentication failed", "unauthorized", "header of type `authorization`"]
        // A 403 with no explanation, or one about authorization, is the key. One that
        // names something else, such as a model the account cannot use, says so.
        if status == 401 || (status == 403 && lowered.isEmpty) || aboutTheKey.contains(where: lowered.contains) {
            return .rejected
        }
        if status == 429 { return .rateLimited }
        if status == 404, lowered.contains("not found for account") {
            return .api("That model is not available to your account.")
        }
        return .api(message ?? "HTTP \(status)")
    }
}

/// Where the keys rest. Behind a protocol so a test never touches a real key.
protocol ChatKeyStore {
    func key(for provider: ChatProvider) -> String?
    @discardableResult func setKey(_ key: String?, for provider: ChatProvider) -> Bool
}

/// The keys, in one file in Nyx's own folder that only this account can read.
///
/// The keychain is not used: Nyx is signed with its own certificate rather than
/// an Apple-issued one, so macOS cannot vouch for it and asks for the login
/// password each time a saved item is read. The file is the same protection the
/// app's other private data has. It is never part of Nyx's preferences, so it is
/// not in a settings export or backup either.
final class ChatFileKeyStore: ChatKeyStore {
    private let fileURL: URL?
    private let directoryURL: URL?
    private var cache: [String: String]?

    init(directoryURL: URL?) {
        self.directoryURL = directoryURL
        fileURL = directoryURL?.appendingPathComponent("Keys.json")
    }

    private func load() -> [String: String] {
        if let cache { return cache }
        var keys: [String: String] = [:]
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = (try? JSONDecoder().decode([String: String].self, from: data)) {
            keys = stored
        }
        cache = keys
        return keys
    }

    func key(for provider: ChatProvider) -> String? {
        let key = load()[provider.rawValue]
        return (key?.isEmpty ?? true) ? nil : key
    }

    @discardableResult
    func setKey(_ key: String?, for provider: ChatProvider) -> Bool {
        var keys = load()
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { keys[provider.rawValue] = nil } else { keys[provider.rawValue] = trimmed }
        guard let directoryURL, let fileURL else { return false }
        if keys.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            cache = keys
            return true
        }
        guard let data = try? JSONEncoder().encode(keys),
              PrivateFileStore.createDirectory(at: directoryURL),
              PrivateFileStore.write(data, to: fileURL) else { return false }
        cache = keys
        return true
    }
}

/// Keys held in memory, for tests.
final class ChatMemoryKeyStore: ChatKeyStore {
    private var keys: [ChatProvider: String] = [:]

    func key(for provider: ChatProvider) -> String? { keys[provider] }

    @discardableResult
    func setKey(_ key: String?, for provider: ChatProvider) -> Bool {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        keys[provider] = trimmed.isEmpty ? nil : trimmed
        return true
    }
}

/// Saved chats: plain text in one owner-only file in the app's folder.
struct ChatHistoryStore {
    let directoryURL: URL?

    private var fileURL: URL? { directoryURL?.appendingPathComponent("Chats.json") }

    func load() -> [ChatConversation] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ChatConversation].self, from: data)) ?? []
    }

    @discardableResult
    func save(_ conversations: [ChatConversation]) -> Bool {
        guard let directoryURL, let fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(conversations),
              PrivateFileStore.createDirectory(at: directoryURL) else { return false }
        return PrivateFileStore.write(data, to: fileURL)
    }

    func deleteAll() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum ChatHistoryRules {
    static let limits = [10, 25, 50, 100]
    static let defaultLimit = 50

    static func clampedLimit(_ value: Int) -> Int { limits.contains(value) ? value : defaultLimit }

    enum Bucket: Int, CaseIterable {
        case today, yesterday, week, month, older
    }

    static func bucket(for date: Date, now: Date, calendar: Calendar = .current) -> Bucket {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return .today
        case 1: return .yesterday
        case 2...7: return .week
        case 8...30: return .month
        default: return .older
        }
    }

    /// The chats grouped by how long ago they were last used, newest first, with
    /// only the groups that have a chat in them.
    static func sections(_ chats: [ChatConversation], now: Date = Date(),
                         calendar: Calendar = .current) -> [(bucket: Bucket, chats: [ChatConversation])] {
        let sorted = chats.sorted { $0.updatedAt > $1.updatedAt }
        return Bucket.allCases.compactMap { bucket in
            let inBucket = sorted.filter { Self.bucket(for: $0.updatedAt, now: now, calendar: calendar) == bucket }
            return inBucket.isEmpty ? nil : (bucket, inBucket)
        }
    }

    /// Newest first, cut to `limit`, with chats that never got a message left out.
    static func trimmed(_ conversations: [ChatConversation], limit: Int) -> [ChatConversation] {
        let kept = conversations.filter { !$0.messages.isEmpty }.sorted { $0.updatedAt > $1.updatedAt }
        return Array(kept.prefix(clampedLimit(limit)))
    }
}

/// A reply split into prose and fenced code, so code gets its own box and a
/// copy button. A fence still open, as in a reply still arriving, counts as code.
enum ChatMarkdown {
    enum Block: Equatable {
        case text(String)
        case code(language: String, text: String)
    }

    /// Prose made to read well as plain inline text: a heading becomes a bold
    /// line and a bullet gets a bullet mark, which inline markdown leaves alone.
    static func prepared(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let indent = line.prefix { $0 == " " }
            let rest = line.dropFirst(indent.count)
            if let marks = rest.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let title = rest[marks.upperBound...].trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? "" : "**" + title.replacingOccurrences(of: "**", with: "") + "**"
            }
            if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
                return indent + "• " + rest.dropFirst(2)
            }
            return String(line)
        }.joined(separator: "\n")
    }

    static func blocks(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        var language = ""
        var inCode = false

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.text(text)) }
            prose = []
        }

        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(language: language, text: code.joined(separator: "\n")))
                    code = []
                    inCode = false
                } else {
                    flushProse()
                    language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
            } else if inCode {
                code.append(line)
            } else {
                prose.append(line)
            }
        }
        if inCode { blocks.append(.code(language: language, text: code.joined(separator: "\n"))) }
        else { flushProse() }
        return blocks
    }
}

/// A light colouring for the code in a reply: comments, strings, numbers,
/// keywords, type names and calls. It knows no language's grammar, only what
/// most of them share, so it is right far more often than it is thorough.
enum ChatSyntax {
    enum Kind: Equatable { case plain, comment, string, number, keyword, type, call }

    struct Run: Equatable {
        let kind: Kind
        let text: String
    }

    private static let hashComments: Set<String> = ["python", "py", "bash", "sh", "shell", "zsh", "ruby", "rb", "yaml", "yml",
                                                    "toml", "r", "perl", "makefile", "dockerfile", "powershell", "ps1", "conf", "ini"]
    private static let dashComments: Set<String> = ["sql", "lua", "haskell", "hs"]

    private static let keywords: Set<String> = [
        "if", "else", "elif", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "yield", "goto",
        "try", "catch", "except", "finally", "throw", "throws", "raise", "with", "as", "in", "is", "not", "and", "or", "await", "async",
        "class", "struct", "enum", "interface", "protocol", "extension", "trait", "impl", "object", "record", "union", "type", "typealias",
        "def", "func", "fn", "fun", "function", "lambda", "let", "var", "val", "const", "final", "static", "public", "private", "protected",
        "internal", "abstract", "override", "virtual", "readonly", "mut", "ref", "out", "new", "delete", "this", "self", "super", "init",
        "import", "from", "package", "module", "use", "using", "namespace", "include", "require", "export", "extends", "implements",
        "int", "long", "short", "byte", "char", "float", "double", "bool", "boolean", "void", "string", "str", "unsigned", "signed",
        "true", "false", "null", "nil", "none", "None", "True", "False", "undefined", "NaN", "pass", "where", "match", "then", "end",
        "select", "insert", "update", "delete", "create", "table", "values", "join", "group", "order", "by", "limit", "echo", "fi", "done",
    ]

    static func runs(_ code: String, language: String) -> [Run] {
        let language = language.lowercased()
        let hash = hashComments.contains(language)
        let dash = dashComments.contains(language)
        let characters = Array(code)
        var runs: [Run] = []
        var plain = ""
        var index = 0

        func flush() {
            if !plain.isEmpty { runs.append(Run(kind: .plain, text: plain)); plain = "" }
        }
        func add(_ kind: Kind, _ text: String) {
            flush()
            runs.append(Run(kind: kind, text: text))
        }
        func starts(with marker: String, at position: Int) -> Bool {
            let marker = Array(marker)
            guard position + marker.count <= characters.count else { return false }
            return Array(characters[position..<position + marker.count]) == marker
        }

        while index < characters.count {
            let character = characters[index]
            // Comments run to the end of the line, or to the closing mark.
            if starts(with: "//", at: index) || (hash && character == "#") || (dash && starts(with: "--", at: index)) {
                var end = index
                while end < characters.count, characters[end] != "\n" { end += 1 }
                add(.comment, String(characters[index..<end]))
                index = end
            } else if starts(with: "/*", at: index) {
                var end = index + 2
                while end < characters.count, !starts(with: "*/", at: end) { end += 1 }
                end = min(characters.count, end + 2)
                add(.comment, String(characters[index..<end]))
                index = end
            } else if character == "\"" || character == "'" || character == "`" {
                let triple = starts(with: String(repeating: String(character), count: 3), at: index)
                var end = index + (triple ? 3 : 1)
                while end < characters.count {
                    if characters[end] == "\\" { end += 2; continue }
                    if triple ? starts(with: String(repeating: String(character), count: 3), at: end) : characters[end] == character {
                        end += triple ? 3 : 1
                        break
                    }
                    // A quote that never closes on its line is not a string, as in "don't".
                    if !triple, character != "`", characters[end] == "\n" { break }
                    end += 1
                }
                end = min(characters.count, end)
                let text = String(characters[index..<end])
                // An apostrophe inside a word, with nothing to close it, stays plain.
                if character == "'", !text.hasSuffix("'") || text.count < 2 { plain.append(character); index += 1 }
                else { add(.string, text); index = end }
            } else if character.isNumber, !(index > 0 && (characters[index - 1].isLetter || characters[index - 1] == "_")) {
                var end = index
                while end < characters.count, characters[end].isNumber || characters[end] == "." || characters[end] == "_"
                        || (characters[end].isLetter && (characters[end].isHexDigit || "xXeEuUlLfF".contains(characters[end]))) {
                    end += 1
                }
                add(.number, String(characters[index..<end]))
                index = end
            } else if character.isLetter || character == "_" {
                var end = index
                while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" { end += 1 }
                let word = String(characters[index..<end])
                var next = end
                while next < characters.count, characters[next] == " " { next += 1 }
                if keywords.contains(word) { add(.keyword, word) }
                else if next < characters.count, characters[next] == "(" { add(.call, word) }
                else if let first = word.first, first.isUppercase, word.count > 1 { add(.type, word) }
                else { plain += word }
                index = end
            } else {
                plain.append(character)
                index += 1
            }
        }
        flush()
        return runs
    }
}
