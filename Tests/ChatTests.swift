import AppKit
import Foundation

/// Chat: what is sent to each service, how its answers are read, where the
/// keys and chats rest, and how the feature joins the island.
enum ChatTests {
    private static func json(_ request: URLRequest) -> [String: Any] {
        guard let body = request.httpBody,
              let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return [:] }
        return object
    }

    private static func data(_ text: String) -> Data { Data(text.utf8) }

    static func run(_ suite: TestSuite) {
        requests(suite)
        files(suite)
        streams(suite)
        models(suite)
        markdown(suite)
        syntax(suite)
        history(suite)
        storage(suite)
        wiring(suite)
        transport(suite)
    }

    // MARK: Transport, against a stand-in server

    private final class Stub: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, chunks: [String]))?
        nonisolated(unsafe) static var seen: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Stub.seen.append(request)
            guard let handler = Stub.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let answer = handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in answer.chunks { client?.urlProtocol(self, didLoad: Data(chunk.utf8)) }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private final class Collector: @unchecked Sendable { var pieces: [String] = [] }
    private final class Box<Value>: @unchecked Sendable { var value: Value? }

    /// Runs async work and keeps the main loop turning while it does, since the
    /// work hands its pieces to the main actor.
    private static func wait<Value>(_ work: @escaping @Sendable () async -> Value) -> Value? {
        let box = Box<Value>()
        Task { box.value = await work() }
        let deadline = Date().addingTimeInterval(15)
        while box.value == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return box.value
    }

    private static func transport(_ suite: TestSuite) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let session = URLSession(configuration: configuration)
        defer { Stub.handler = nil }
        let message = ChatMessage(role: .user, text: "Hi")

        func reply(_ provider: ChatProvider, status: Int = 200, chunks: [String], connected: Bool = true) -> (pieces: [String], failure: ChatFailure?, ended: Bool) {
            Stub.handler = connected ? { _ in (status, chunks) } : nil
            let request = ChatAPI.chatRequest(provider: provider, model: "m", apiKey: "KEY-12345678", system: nil, messages: [message])
            let collector = Collector()
            let outcome = wait { () -> (failure: ChatFailure?, threw: Bool) in
                do { return (try await ChatTransport.stream(request, provider: provider, session: session) { collector.pieces.append($0) }, false) }
                catch { return (nil, true) }
            }
            guard let outcome, !outcome.threw else { return (collector.pieces, nil, false) }
            return (collector.pieces, outcome.failure, true)
        }

        // Lines split across the network's chunks are still whole lines.
        let claude = reply(.claude, chunks: [
            "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_d",
            "elta\",\"text\":\"Hel\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}\n\n",
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
        ])
        suite.expect(claude.ended && claude.pieces == ["Hel", "lo"] && claude.failure == nil,
                     "chat transport: Claude's stream arrives piece by piece, even split mid-line")

        let openai = reply(.openai, chunks: [
            "data: {\"choices\":[{\"delta\":{\"content\":\"A\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"B\"}}]}\n\n",
            "data: [DONE]\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"never\"}}]}\n\n",
        ])
        suite.expect(openai.ended && openai.pieces == ["A", "B"] && openai.failure == nil,
                     "chat transport: nothing after [DONE] is read")

        let gemini = reply(.gemini, chunks: ["data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hey\"}]}}]}\r\n\r\n"])
        suite.expect(gemini.ended && gemini.pieces == ["Hey"] && gemini.failure == nil,
                     "chat transport: a stream that ends without a closing event is complete")

        let rejected = reply(.openai, status: 401, chunks: [#"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#])
        suite.expect(rejected.failure == .rejected && rejected.pieces.isEmpty, "chat transport: a 401 says the key was refused")
        let limited = reply(.claude, status: 429, chunks: [#"{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#])
        suite.expect(limited.failure == .rateLimited, "chat transport: a 429 says the limit is reached")
        let broken = reply(.nvidia, status: 500, chunks: [#"{"error":{"message":"Server exploded"}}"#])
        suite.expect(broken.failure == .api("Server exploded"), "chat transport: another failure carries the service's words")
        let midway = reply(.claude, chunks: [
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Par"}}"# + "\n\n",
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"# + "\n\n",
        ])
        suite.expect(midway.pieces == ["Par"] && midway.failure == .api("Overloaded"),
                     "chat transport: an error after some text keeps the text and reports the error")

        let unreachable = reply(.openai, chunks: [], connected: false)
        suite.expect(!unreachable.ended, "chat transport: a connection that fails throws instead of answering")

        // NVIDIA: every listed model is tried; the ones that answer are the account's.
        func sweepOutcome(_ answers: [String: Int]) -> Result<[ChatModel], ChatFailure>? {
            Stub.handler = { request in
                let model = ((try? JSONSerialization.jsonObject(with: request.bodyStreamData ?? Data())) as? [String: Any])?["model"] as? String ?? ""
                return (answers[model] ?? 404, [#"{"status":404,"detail":"Function 'f': Not found for account 'a'"}"#])
            }
            let models = [ChatModel(id: "a/zeta"), ChatModel(id: "nvidia/nemotron-3.5-lightning-30b-a3b"), ChatModel(id: "openai/gpt-oss-20b"), ChatModel(id: "b/dead")]
            return wait { await ChatTransport.sweep(provider: .nvidia, key: "nvapi-key-123456789", models: models, session: session) }
        }
        if case .success(let list)? = sweepOutcome(["a/zeta": 200, "openai/gpt-oss-20b": 429, "nvidia/nemotron-3.5-lightning-30b-a3b": 410]) {
            suite.expect(list.map(\.id) == ["openai/gpt-oss-20b", "a/zeta"],
                         "chat transport: only the models that answer are kept, preferred first, a limit reached counting as an answer")
        } else { suite.expect(false, "chat transport: only the models that answer are kept") }
        if case .failure(let failure)? = sweepOutcome(["a/zeta": 401, "openai/gpt-oss-20b": 200]) {
            suite.expect(failure == .rejected, "chat transport: a refused key ends the search")
        } else { suite.expect(false, "chat transport: a refused key ends the search") }
        if case .failure(let failure)? = sweepOutcome([:]) {
            suite.expect(failure == .api("That model is not available to your account."),
                         "chat transport: with no model open to the account, the reason is shown")
        } else { suite.expect(false, "chat transport: with no model open to the account, the reason is shown") }

        // The whole path: NVIDIA's list is open, the account's models are what is left.
        Stub.handler = { request in
            if request.url?.path.hasSuffix("/models") == true {
                return (200, [#"{"data":[{"id":"nvidia/nemotron-3.5-lightning-30b-a3b"},{"id":"nvidia/nemotron-3-super-120b-a12b"},{"id":"nvidia/embed-qa-4"}]}"#])
            }
            let model = ((try? JSONSerialization.jsonObject(with: request.bodyStreamData ?? Data())) as? [String: Any])?["model"] as? String ?? ""
            return model == "nvidia/nemotron-3.5-lightning-30b-a3b" ? (200, ["{}"]) : (404, [#"{"detail":"Function 'f': Not found for account 'a'"}"#])
        }
        let available = wait { await ChatTransport.availableModels(provider: .nvidia, key: "nvapi-key-123456789", session: session) }
        if case .success(let list)? = available {
            suite.expect(list.map(\.id) == ["nvidia/nemotron-3.5-lightning-30b-a3b"], "chat transport: NVIDIA's available models are the ones that answer")
        } else { suite.expect(false, "chat transport: NVIDIA's available models are the ones that answer") }

        // What went over the wire.
        Stub.seen = []
        _ = reply(.openai, chunks: ["data: [DONE]\n\n"])
        suite.expect(Stub.seen.count == 1 && Stub.seen[0].value(forHTTPHeaderField: "Authorization") == "Bearer KEY-12345678"
                        && !(Stub.seen[0].url?.absoluteString ?? "").contains("KEY-12345678"),
                     "chat transport: the key goes in the header and not in the address")

        // Models
        Stub.handler = { _ in (200, [#"{"data":[{"id":"gpt-5","created":1800000000},{"id":"whisper-1","created":1}]}"#]) }
        let listed = wait { await ChatTransport.models(provider: .openai, key: "KEY-12345678", session: session) }
        if case .success(let list)? = listed { suite.expect(list.map(\.id) == ["gpt-5"], "chat transport: the model list is read and filtered") }
        else { suite.expect(false, "chat transport: the model list is read and filtered") }
        Stub.handler = { _ in (401, [#"{"error":{"message":"Incorrect API key provided"}}"#]) }
        let refused = wait { await ChatTransport.models(provider: .openai, key: "KEY-12345678", session: session) }
        if case .failure(let failure)? = refused { suite.expect(failure == .rejected, "chat transport: a wrong key fails the model list as rejected") }
        else { suite.expect(false, "chat transport: a wrong key fails the model list as rejected") }
        Stub.handler = nil
        let offline = wait { await ChatTransport.models(provider: .openai, key: "KEY-12345678", session: session) }
        if case .failure(let failure)? = offline { suite.expect(failure == .unreachable, "chat transport: no connection is unreachable") }
        else { suite.expect(false, "chat transport: no connection is unreachable") }

        suite.expect(ChatTransport.isCancellation(CancellationError()) && ChatTransport.isCancellation(URLError(.cancelled))
                        && !ChatTransport.isCancellation(URLError(.timedOut)),
                     "chat transport: stopping a reply is told apart from a fault")
    }

    // MARK: Files

    private static func files(_ suite: TestSuite) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nyx-chat-files-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let csv = directory.appendingPathComponent("sales.csv")
        try? "a,b\n1,2\n".write(to: csv, atomically: true, encoding: .utf8)
        if case .success(let file) = ChatFileReader.read(csv) {
            suite.expect(file.name == "sales.csv" && file.text == "a,b\n1,2" && file.images.isEmpty && !file.truncated,
                         "chat files: a CSV is read as text")
        } else { suite.expect(false, "chat files: a CSV is read as text") }

        let big = directory.appendingPathComponent("big.txt")
        try? String(repeating: "x", count: ChatFileReader.maximumText + 500).write(to: big, atomically: true, encoding: .utf8)
        if case .success(let file) = ChatFileReader.read(big) {
            suite.expect(file.text?.count == ChatFileReader.maximumText && file.truncated,
                         "chat files: a long file is cut and marked as cut")
        } else { suite.expect(false, "chat files: a long file is cut and marked as cut") }

        let blank = directory.appendingPathComponent("blank.txt")
        try? "  \n".write(to: blank, atomically: true, encoding: .utf8)
        let odd = directory.appendingPathComponent("tool.exe")
        try? "x".write(to: odd, atomically: true, encoding: .utf8)
        let old = directory.appendingPathComponent("old.xls")
        try? "x".write(to: old, atomically: true, encoding: .utf8)
        suite.expect(ChatFileReader.read(blank) == .failure(.empty("blank.txt"))
                        && ChatFileReader.read(odd) == .failure(.unsupported("tool.exe"))
                        && ChatFileReader.read(directory.appendingPathComponent("missing.txt")) == .failure(.unreadable("missing.txt")),
                     "chat files: an empty, unknown or missing file is refused with its name")
        if case .failure(let error) = ChatFileReader.read(old) {
            suite.expect(error.message.contains("old.xls"), "chat files: an old .xls says it cannot be read")
        } else { suite.expect(false, "chat files: an old .xls says it cannot be read") }

        let image = NSImage(size: NSSize(width: 3000, height: 1000), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        if let png = image.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) })?.representation(using: .png, properties: [:]) {
            let url = directory.appendingPathComponent("wide.png")
            try? png.write(to: url)
            if case .success(let file) = ChatFileReader.read(url), let picture = file.images.first,
               let jpeg = Data(base64Encoded: picture.base64), let decoded = NSImage(data: jpeg) {
                suite.expect(picture.mime == "image/jpeg" && file.text == nil
                                && decoded.representations.first.map { CGFloat($0.pixelsWide) <= ChatFileReader.imageEdge } == true,
                             "chat files: a picture is shrunk and sent as a JPEG")
            } else { suite.expect(false, "chat files: a picture is shrunk and sent as a JPEG") }
        }

        suite.expect(ChatFileReader.sheetNames(in: #"<sheets><sheet name="Q1 &amp; Q2" sheetId="1" r:id="rId1"/></sheets>"#) == ["Q1 & Q2"]
                        && ChatFileReader.sharedStrings(in: "<sst><si><t>Name</t></si><si><r><t>Ab</t></r><r><t>c</t></r></si></sst>") == ["Name", "Abc"],
                     "chat files: spreadsheet sheet names and shared strings are read")
        let rows = ChatFileReader.rows(
            in: #"<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><v>42</v></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>x</t></is></c></row>"#,
            shared: ["Name"])
        suite.expect(rows == ["Name\t42", "x"], "chat files: spreadsheet rows come out tab-separated")

        // How the files reach each service.
        var message = ChatMessage(role: .user, text: "Summarise")
        message.fileText = ChatMessage.fileBlock([ChatPendingFile(name: "a.txt", symbol: "doc", text: "hello", truncated: true)])
        message.images = [ChatImage(mime: "image/jpeg", base64: "QUJD")]
        suite.expect(message.requestText.hasPrefix("Attached file \"a.txt\" (cut short):") && message.requestText.hasSuffix("Summarise"),
                     "chat files: the file's text goes before the question, under its name")

        let claude = json(ChatAPI.chatRequest(provider: .claude, model: "m", apiKey: "k", system: nil, messages: [message]))
        let claudeContent = ((claude["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        suite.expect(claudeContent.first?["type"] as? String == "image"
                        && (claudeContent.first?["source"] as? [String: String])?["media_type"] == "image/jpeg"
                        && (claudeContent.first?["source"] as? [String: String])?["data"] == "QUJD"
                        && claudeContent.last?["type"] as? String == "text",
                     "chat files: Claude gets pictures as base64 blocks before the text")
        let openai = json(ChatAPI.chatRequest(provider: .nvidia, model: "m", apiKey: "k", system: nil, messages: [message]))
        let openaiContent = ((openai["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        suite.expect(openaiContent.first?["type"] as? String == "text"
                        && (openaiContent.last?["image_url"] as? [String: String])?["url"] == "data:image/jpeg;base64,QUJD",
                     "chat files: NVIDIA and OpenAI get pictures as data addresses")
        let gemini = json(ChatAPI.chatRequest(provider: .gemini, model: "m", apiKey: "k", system: nil, messages: [message]))
        let parts = ((gemini["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]]) ?? []
        suite.expect((parts.first?["inline_data"] as? [String: String])?["data"] == "QUJD" && parts.last?["text"] != nil,
                     "chat files: Gemini gets pictures as inline data")

        let plain = json(ChatAPI.chatRequest(provider: .claude, model: "m", apiKey: "k", system: nil,
                                             messages: [ChatMessage(role: .user, text: "Hi")]))
        suite.expect(((plain["messages"] as? [[String: Any]])?.first?["content"] as? String) == "Hi",
                     "chat files: a message with no picture is still plain text")

        message.files = [ChatFileInfo(name: "a.txt", symbol: "doc")]
        if let saved = try? JSONEncoder().encode(message), let back = try? JSONDecoder().decode(ChatMessage.self, from: saved) {
            suite.expect(back.files == message.files && back.fileText == message.fileText && back.images.isEmpty
                            && !String(decoding: saved, as: UTF8.self).contains("QUJD"),
                         "chat files: a saved chat keeps file names and text but never the pictures")
        } else { suite.expect(false, "chat files: a saved chat keeps file names and text but never the pictures") }
        let oldChat = Data(#"{"id":"\#(UUID().uuidString)","role":"user","text":"Hi"}"#.utf8)
        suite.expect((try? JSONDecoder().decode(ChatMessage.self, from: oldChat))?.files == [],
                     "chat files: chats saved before files existed still open")
    }

    // MARK: Requests

    private static func requests(_ suite: TestSuite) {
        var question = ChatMessage(role: .user, text: "What is this?")
        question.context = "let x = 1"
        let reply = ChatMessage(role: .assistant, text: "A constant.")
        let followUp = ChatMessage(role: .user, text: "And var?")
        let empty = ChatMessage(role: .assistant, text: "")
        let messages = [question, reply, followUp, empty]

        let claude = ChatAPI.chatRequest(provider: .claude, model: "claude-x", apiKey: "sk-ant-secret",
                                         system: " Be brief. ", messages: messages)
        let claudeBody = json(claude)
        suite.expect(claude.url?.absoluteString == "https://api.anthropic.com/v1/messages" && claude.httpMethod == "POST",
                     "chat: Claude is asked at its messages endpoint")
        suite.expect(claude.value(forHTTPHeaderField: "x-api-key") == "sk-ant-secret"
                        && claude.value(forHTTPHeaderField: "anthropic-version") == ChatAPI.anthropicVersion,
                     "chat: Claude gets the key and version in headers")
        suite.expect(claudeBody["model"] as? String == "claude-x" && claudeBody["stream"] as? Bool == true
                        && claudeBody["max_tokens"] as? Int == ChatAPI.claudeMaxTokens
                        && claudeBody["system"] as? String == "Be brief.",
                     "chat: Claude is sent the model, a token limit, streaming and the trimmed instructions")
        let claudeMessages = claudeBody["messages"] as? [[String: String]] ?? []
        suite.expect(claudeMessages.count == 3 && claudeMessages.map { $0["role"] } == ["user", "assistant", "user"],
                     "chat: an empty reply is never sent back")
        suite.expect(claudeMessages.first?["content"]?.contains("let x = 1") == true
                        && claudeMessages.first?["content"]?.hasSuffix("What is this?") == true,
                     "chat: attached text goes ahead of the question")

        let openai = ChatAPI.chatRequest(provider: .openai, model: "gpt-x", apiKey: "sk-openai",
                                         system: "Be brief.", messages: messages)
        let openaiList = json(openai)["messages"] as? [[String: String]] ?? []
        suite.expect(openai.url?.absoluteString == "https://api.openai.com/v1/chat/completions"
                        && openai.value(forHTTPHeaderField: "Authorization") == "Bearer sk-openai",
                     "chat: OpenAI takes the key as a bearer token")
        suite.expect(openaiList.first?["role"] == "system" && openaiList.count == 4,
                     "chat: OpenAI gets the instructions as its first message")

        let nvidia = ChatAPI.chatRequest(provider: .nvidia, model: "meta/llama-3.3-70b-instruct", apiKey: "nvapi-abc123", system: nil, messages: messages)
        suite.expect(nvidia.url?.absoluteString == "https://integrate.api.nvidia.com/v1/chat/completions"
                        && nvidia.value(forHTTPHeaderField: "Authorization") == "Bearer nvapi-abc123"
                        && json(nvidia)["model"] as? String == "meta/llama-3.3-70b-instruct",
                     "chat: NVIDIA is asked the way OpenAI is, at its own address, with its model name as given")
        suite.expect((json(nvidia)["messages"] as? [[String: String]])?.first?["role"] == "user",
                     "chat: no instructions means no system message")

        let gemini = ChatAPI.chatRequest(provider: .gemini, model: "gemini-x", apiKey: "AIza-secret",
                                         system: "Be brief.", messages: messages)
        let geminiBody = json(gemini)
        suite.expect(gemini.url?.path.hasSuffix("/models/gemini-x:streamGenerateContent") == true
                        && gemini.url?.query == "alt=sse",
                     "chat: Gemini streams from its own method")
        suite.expect(gemini.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-secret"
                        && !(gemini.url?.absoluteString ?? "").contains("AIza-secret"),
                     "chat: Gemini's key is a header, never part of the address")
        let contents = geminiBody["contents"] as? [[String: Any]] ?? []
        suite.expect(contents.map { $0["role"] as? String } == ["user", "model", "user"],
                     "chat: Gemini calls its own side the model")
        suite.expect(geminiBody["systemInstruction"] != nil, "chat: Gemini gets instructions as a system instruction")

        for provider in ChatProvider.allCases {
            let request = ChatAPI.chatRequest(provider: provider, model: "m", apiKey: "KEY-12345678", system: nil, messages: [question])
            suite.expect(request.url?.scheme == "https" && !(request.url?.absoluteString ?? "").contains("KEY-12345678"),
                         "chat: \(provider.displayName) is reached over https with no key in the address")
            let models = ChatAPI.modelsRequest(provider: provider, apiKey: "KEY-12345678")
            suite.expect(models.url?.scheme == "https" && !(models.url?.absoluteString ?? "").contains("KEY-12345678"),
                         "chat: \(provider.displayName)'s model list is asked for over https with no key in the address")
        }

        suite.expect(ChatConversation.title(from: "  Hello there\nsecond line") == "Hello there",
                     "chat: a chat is named by its first line")
        suite.expect(ChatConversation.title(from: String(repeating: "a", count: 80)).count == 48,
                     "chat: a long first line is cut with an ellipsis")
        let nvKey = "nvapi-AbCdEf0123456789_-xYzAbCdEf0123456789abcdefghijklmnopq"
        suite.expect(ChatProvider.extractKey(from: "  \(nvKey)\n") == nvKey, "chat: a pasted key alone is taken as it is")
        suite.expect(ChatProvider.extractKey(from: "client = OpenAI(\n  base_url = \"https://integrate.api.nvidia.com/v1\",\n  api_key = \"\(nvKey)\"\n)") == nvKey,
                     "chat: the key is found inside a Python snippet")
        suite.expect(ChatProvider.extractKey(from: "const openai = new OpenAI({ apiKey: '\(nvKey)', baseURL: 'https://integrate.api.nvidia.com/v1' })") == nvKey,
                     "chat: the key is found inside a Node snippet")
        suite.expect(ChatProvider.extractKey(from: "curl https://integrate.api.nvidia.com/v1/chat/completions \\\n  -H \"Authorization: Bearer \(nvKey)\" \\\n  -d '{\"model\": \"x\"}'") == nvKey,
                     "chat: the key is found inside a shell command")
        suite.expect(ChatProvider.extractKey(from: "\"\(nvKey)\"") == nvKey && ChatProvider.extractKey(from: "export KEY=sk-ant-api03-abcdefghijklmnopqrstu") == "sk-ant-api03-abcdefghijklmnopqrstu",
                     "chat: quotes and an export line are stripped away")
        let noKeySnippet = "from openai import OpenAI\nclient = OpenAI(\n  base_url = \"https://integrate.api.nvidia.com/v1\",\n  api_key = \"$NVIDIA_API_KEY\"\n)"
        suite.expect(ChatProvider.extractKey(from: noKeySnippet) == nil && ChatProvider.isSnippetWithoutKey(noKeySnippet)
                        && !ChatProvider.isSnippetWithoutKey("hello there\nfriend") && !ChatProvider.isSnippetWithoutKey(nvKey),
                     "chat: a snippet that still says $NVIDIA_API_KEY is recognised as having no key"
                     )
        suite.expect(ChatProvider.extractKey(from: "import os\nprint('hello world')") == nil && ChatProvider.extractKey(from: "") == nil,
                     "chat: code with no key in it has no key")
        suite.expect(ChatProvider.looksLikeKey("sk-ant-api03-abcdefghijkl") && !ChatProvider.looksLikeKey("hello world there")
                        && !ChatProvider.looksLikeKey("short") && !ChatProvider.looksLikeKey("two words here"),
                     "chat: a pasted key has no spaces and some length")
    }

    // MARK: Streams

    private static func streams(_ suite: TestSuite) {
        let claudeDelta = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#
        suite.expect(ChatAPI.event(fromLine: claudeDelta, provider: .claude) == .text("Hel"), "chat: Claude's text arrives as text")
        suite.expect(ChatAPI.event(fromLine: "event: content_block_delta", provider: .claude) == nil,
                     "chat: event names carry nothing to show")
        suite.expect(ChatAPI.event(fromLine: #"data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{"}}"#,
                                   provider: .claude) == nil,
                     "chat: only text deltas are text")
        suite.expect(ChatAPI.event(fromLine: #"data: {"type":"message_stop"}"#, provider: .claude) == .done, "chat: Claude says when it is done")
        suite.expect(ChatAPI.event(fromLine: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
                                   provider: .claude) == .failed("Overloaded"),
                     "chat: an error in the stream is reported in the service's words")

        let openaiDelta = #"data: {"choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}"#
        suite.expect(ChatAPI.event(fromLine: openaiDelta, provider: .openai) == .text("Hi")
                        && ChatAPI.event(fromLine: openaiDelta, provider: .nvidia) == .text("Hi"),
                     "chat: OpenAI and NVIDIA send text in a choice's delta")
        suite.expect(ChatAPI.event(fromLine: "data: [DONE]", provider: .openai) == .done, "chat: [DONE] ends the stream")
        suite.expect(ChatAPI.event(fromLine: #"data: {"choices":[{"delta":{"role":"assistant","content":""}}]}"#, provider: .openai) == nil
                        && ChatAPI.event(fromLine: #"data: {"choices":[{"delta":{"reasoning_content":"thinking"}}]}"#, provider: .nvidia) == nil,
                     "chat: empty pieces and a model's private reasoning are not shown")
        suite.expect(ChatAPI.event(fromLine: ": keep-alive", provider: .openai) == nil && ChatAPI.event(fromLine: "data: not json", provider: .openai) == nil,
                     "chat: keep-alives and noise are skipped")
        suite.expect(ChatAPI.event(fromLine: #"data: {"error":{"message":"You exceeded your quota","type":"insufficient_quota"}}"#,
                                   provider: .openai) == .failed("You exceeded your quota"),
                     "chat: OpenAI's in-stream error is reported")

        let geminiChunk = #"data: {"candidates":[{"content":{"parts":[{"text":"Hello"},{"text":" there"}],"role":"model"}}]}"#
        suite.expect(ChatAPI.event(fromLine: geminiChunk, provider: .gemini) == .text("Hello there"), "chat: Gemini's parts are joined")
        let thought = #"data: {"candidates":[{"content":{"parts":[{"text":"hmm","thought":true},{"text":"Answer"}]}}]}"#
        suite.expect(ChatAPI.event(fromLine: thought, provider: .gemini) == .text("Answer"), "chat: Gemini's thinking is left out")
        suite.expect(ChatAPI.event(fromLine: #"data: {"promptFeedback":{"blockReason":"SAFETY"}}"#, provider: .gemini) == .failed("Blocked: SAFETY"),
                     "chat: a blocked prompt is said to be blocked")
        suite.expect(ChatAPI.event(fromLine: #"data: {"candidates":[{"finishReason":"STOP"}]}"#, provider: .gemini) == nil,
                     "chat: a plain finish adds no text")

        suite.expect(ChatAPI.failure(status: 401, message: "x") == .rejected && ChatAPI.failure(status: 403, message: nil) == .rejected,
                     "chat: 401 and 403 mean the key was not accepted")
        suite.expect(ChatAPI.failure(status: 400, message: "API key not valid. Please pass a valid API key.") == .rejected,
                     "chat: Gemini says a wrong key with a 400")
        suite.expect(ChatAPI.failure(status: 429, message: nil) == .rateLimited, "chat: 429 is a limit")
        suite.expect(ChatAPI.failure(status: 500, message: "Boom") == .api("Boom") && ChatAPI.failure(status: 500, message: nil) == .api("HTTP 500"),
                     "chat: anything else shows the service's words, or the status")
        suite.expect(ChatAPI.failureMessage(body: data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)) == "invalid x-api-key"
                        && ChatAPI.failureMessage(body: data(#"{"error":{"code":400,"message":"Bad","status":"INVALID_ARGUMENT"}}"#)) == "Bad"
                        && ChatAPI.failureMessage(body: data("<html>")) == nil,
                     "chat: a refused request's message is found in each service's shape")
    }

    // MARK: Models

    private static func models(_ suite: TestSuite) {
        let claude = ChatAPI.parseModels(data(#"""
        {"data":[{"id":"claude-opus-9","display_name":"Claude Opus 9","created_at":"2026-05-01T00:00:00Z"},
                 {"id":"claude-sonnet-9","display_name":"Claude Sonnet 9","created_at":"2026-04-01T00:00:00Z"}],"has_more":false}
        """#), provider: .claude)
        suite.expect(claude.map(\.id) == ["claude-opus-9", "claude-sonnet-9"] && claude.first?.name == "Claude Opus 9" && claude.first?.created != nil,
                     "chat: Claude's models keep their names and order")
        suite.expect(ChatAPI.defaultModel(in: claude, provider: .claude) == "claude-sonnet-9", "chat: Claude starts on Sonnet")
        suite.expect(ChatAPI.defaultModel(in: [], provider: .claude) == ChatProvider.claude.fallbackModel, "chat: with no list, the fallback model")

        let openai = ChatAPI.parseModels(data(#"""
        {"data":[{"id":"text-embedding-3-small","created":1},{"id":"whisper-1","created":2},
                 {"id":"gpt-4o","created":1700000000},{"id":"gpt-5","created":1800000000},
                 {"id":"gpt-5-mini","created":1800000001},{"id":"gpt-5-2026-01-01","created":1800000002},
                 {"id":"gpt-4o-audio-preview","created":1800000003},{"id":"o3","created":1750000000},
                 {"id":"dall-e-3","created":3},{"id":"gpt-image-1","created":4}]}
        """#), provider: .openai)
        suite.expect(Set(openai.map(\.id)) == ["gpt-4o", "gpt-5", "gpt-5-mini", "gpt-5-2026-01-01", "o3"],
                     "chat: OpenAI's list keeps chat models and drops embeddings, speech and images")
        suite.expect(openai.first?.id == "gpt-5-2026-01-01", "chat: OpenAI's newest model leads")
        suite.expect(ChatAPI.defaultModel(in: openai, provider: .openai) == "gpt-5",
                     "chat: OpenAI starts on the newest plain model, not a mini, a dated copy or a preview")

        let gemini = ChatAPI.parseModels(data(#"""
        {"models":[{"name":"models/gemini-2.5-flash","displayName":"Gemini 2.5 Flash","supportedGenerationMethods":["generateContent"]},
                   {"name":"models/gemini-3-flash","displayName":"Gemini 3 Flash","supportedGenerationMethods":["generateContent","countTokens"]},
                   {"name":"models/gemini-3-flash-lite","supportedGenerationMethods":["generateContent"]},
                   {"name":"models/text-embedding-004","supportedGenerationMethods":["embedContent"]},
                   {"name":"models/gemini-3-pro","supportedGenerationMethods":["generateContent"]},
                   {"name":"models/gemini-2.5-flash-image","supportedGenerationMethods":["generateContent"]}]}
        """#), provider: .gemini)
        suite.expect(gemini.map(\.id) == ["gemini-3-pro", "gemini-3-flash-lite", "gemini-3-flash", "gemini-2.5-flash"],
                     "chat: Gemini's list drops other methods and images, strips models/, newest name first")
        suite.expect(ChatAPI.defaultModel(in: gemini, provider: .gemini) == "gemini-3-flash",
                     "chat: Gemini starts on the newest Flash that is not a Lite")

        let nvidia = ChatAPI.parseModels(data(#"""
        {"object":"list","data":[{"id":"nvidia/nv-embedqa-e5-v5"},{"id":"nvidia/llama-3.2-nv-rerankqa-1b-v2"},
         {"id":"meta/llama-3.3-70b-instruct"},{"id":"deepseek-ai/deepseek-r1"},{"id":"black-forest-labs/flux.1-dev"},
         {"id":"nvidia/llama-3.1-nemoguard-8b-content-safety"},{"id":"abacusai/dracarys-llama-3.1-70b-instruct"},
         {"id":"some-org/plain-model"}]}
        """#), provider: .nvidia)
        suite.expect(nvidia.map(\.id) == ["abacusai/dracarys-llama-3.1-70b-instruct", "deepseek-ai/deepseek-r1", "meta/llama-3.3-70b-instruct", "some-org/plain-model"],
                     "chat: NVIDIA's catalog drops embedding, ranking, image and safety models, and chat models lead")
        let live = [ChatModel(id: "z/other"), ChatModel(id: "openai/gpt-oss-20b"), ChatModel(id: "nvidia/nemotron-3-super-120b-a12b")]
        suite.expect(ChatAPI.defaultModel(in: live, provider: .nvidia) == "nvidia/nemotron-3-super-120b-a12b",
                     "chat: NVIDIA starts on the first preferred model its catalog still lists")
        suite.expect(ChatAPI.defaultModel(in: [ChatModel(id: "x/a"), ChatModel(id: "x/b")], provider: .nvidia) == "x/a"
                        && ChatAPI.defaultModel(in: [], provider: .nvidia) == ChatProvider.nvidia.fallbackModel,
                     "chat: otherwise the first it lists, or the fallback")
        suite.expect(ChatAPI.probeCandidates(from: live) == ["nvidia/nemotron-3-super-120b-a12b", "openai/gpt-oss-20b", "z/other"],
                     "chat: NVIDIA's models are tried preferred first, then as listed")
        suite.expect(ChatAPI.probeCandidates(from: (0..<80).map { ChatModel(id: "m/\($0)") }).count == 60,
                     "chat: a long catalog is tried up to a limit")
        let probe = ChatAPI.probeRequest(provider: .nvidia, model: "m/x", apiKey: "nvapi-k")
        suite.expect(json(probe)["max_tokens"] as? Int == 1 && json(probe)["stream"] as? Bool == false
                        && probe.value(forHTTPHeaderField: "Authorization") == "Bearer nvapi-k",
                     "chat: the test message asks for one token, without streaming")
        suite.expect(ChatAPI.failureMessage(body: data(#"{"type":"about:blank","title":"Gone","status":410,"detail":"The model has reached its end of life"}"#))
                        == "The model has reached its end of life",
                     "chat: NVIDIA's problem-details errors are read")
        suite.expect(ChatAPI.failure(status: 403, message: "Authorization failed") == .rejected
                        && ChatAPI.failure(status: 403, message: "Account not entitled to model x") == .api("Account not entitled to model x")
                        && ChatAPI.failure(status: 410, message: "Gone for good") == .api("Gone for good")
                        && ChatAPI.failure(status: 404, message: "Function 'abc': Not found for account 'xyz'") == .api("That model is not available to your account."),
                     "chat: a 403 about the key is the key; one about a model says so")
        suite.expect(ChatAPI.parseModels(data("garbage"), provider: .openai).isEmpty, "chat: an unreadable list is empty, not a crash")
    }

    // MARK: Markdown

    private static func markdown(_ suite: TestSuite) {
        suite.expect(ChatMarkdown.blocks("Just words.\nTwo lines.") == [.text("Just words.\nTwo lines.")], "chat: prose stays one block")
        suite.expect(ChatMarkdown.blocks("Try this:\n```swift\nlet a = 1\nprint(a)\n```\nDone.")
                        == [.text("Try this:"), .code(language: "swift", text: "let a = 1\nprint(a)"), .text("Done.")],
                     "chat: fenced code is split out with its language")
        suite.expect(ChatMarkdown.blocks("```\nlet a = 1")
                        == [.code(language: "", text: "let a = 1")],
                     "chat: a fence still open, as in a reply arriving, is code")
        suite.expect(ChatMarkdown.blocks("") == [] && ChatMarkdown.blocks("\n\n") == [], "chat: nothing is no blocks")
        suite.expect(ChatMarkdown.blocks("```a\n1\n```\n```b\n2\n```").count == 2, "chat: two fences are two blocks")
        suite.expect(ChatMarkdown.prepared("# Title\n- one\n  * two\nplain **bold**") == "**Title**\n• one\n  • two\nplain **bold**",
                     "chat: headings become bold lines and bullets get a mark")
        suite.expect(ChatMarkdown.prepared("2 * 3 = 6\n-5 is negative") == "2 * 3 = 6\n-5 is negative",
                     "chat: maths and negative numbers are left alone")
    }

    // MARK: Syntax

    private static func syntax(_ suite: TestSuite) {
        func kinds(_ code: String, _ language: String = "") -> [String] {
            ChatSyntax.runs(code, language: language).filter { $0.kind != .plain }.map { "\($0.kind):\($0.text)" }
        }
        suite.expect(kinds("int x = 42; // count") == ["keyword:int", "number:42", "comment:// count"],
                     "chat syntax: a keyword, a number and a comment are told apart")
        suite.expect(kinds("for (int i = 0; i < n; i++) {") == ["keyword:for", "keyword:int", "number:0"],
                     "chat syntax: a loop header's keywords and number")
        suite.expect(kinds("print(\"hi there\")") == ["call:print", "string:\"hi there\""], "chat syntax: a call and a string")
        suite.expect(kinds("List<String> names = new ArrayList<>();") == ["type:List", "type:String", "keyword:new", "type:ArrayList"],
                     "chat syntax: capitalised names are types")
        suite.expect(kinds("x = 1 # note", "python") == ["number:1", "comment:# note"] && kinds("x = 1 # note") == ["number:1"],
                     "chat syntax: # starts a comment only in languages that use it")
        suite.expect(kinds("a /* inner\nlines */ b") == ["comment:/* inner\nlines */"], "chat syntax: a block comment can span lines")
        suite.expect(kinds("it's fine") == [] && kinds("say 'hi'") == ["string:'hi'"],
                     "chat syntax: an apostrophe in a word is not a string")
        suite.expect(kinds("v2 = x1 + 0xFF") == ["number:0xFF"], "chat syntax: digits inside a name are not numbers")
        suite.expect(ChatSyntax.runs("def f(a):\n    return a", language: "python").map(\.text).joined() == "def f(a):\n    return a",
                     "chat syntax: the runs always add back up to the code")
        suite.expect(ChatSyntax.runs("\"unclosed", language: "").map(\.text).joined() == "\"unclosed" && ChatSyntax.runs("", language: "").isEmpty,
                     "chat syntax: unfinished code, as in a reply still arriving, is kept whole")
    }

    // MARK: History

    private static func history(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 15))!
        func chat(_ title: String, daysAgo: Double, provider: ChatProvider = .claude) -> ChatConversation {
            let date = now.addingTimeInterval(-daysAgo * 86_400)
            return ChatConversation(title: title, provider: provider, model: "m", createdAt: date, updatedAt: date,
                                    messages: [ChatMessage(role: .user, text: title)])
        }
        let bucket: (Double) -> ChatHistoryRules.Bucket = { ChatHistoryRules.bucket(for: now.addingTimeInterval(-$0 * 86_400), now: now, calendar: calendar) }
        suite.expect(bucket(0) == .today && bucket(0.4) == .today, "chat history: this morning is today")
        suite.expect(bucket(1) == .yesterday && bucket(2) == .week && bucket(7) == .week && bucket(8) == .month
                        && bucket(30) == .month && bucket(31) == .older && bucket(400) == .older,
                     "chat history: the groups are today, yesterday, the last week, the last month and older")
        let grouped = ChatHistoryRules.sections([chat("old", daysAgo: 90), chat("a", daysAgo: 0.1), chat("b", daysAgo: 0.05), chat("w", daysAgo: 3)],
                                                now: now, calendar: calendar)
        suite.expect(grouped.map(\.bucket) == [.today, .week, .older] && grouped[0].chats.map(\.title) == ["b", "a"],
                     "chat history: only groups with a chat are listed, and each is newest first")
        suite.expect(ChatHistoryRules.sections([], now: now, calendar: calendar).isEmpty, "chat history: no chats, no groups")
    }

    // MARK: Storage

    private static func storage(_ suite: TestSuite) {
        let keys = ChatMemoryKeyStore()
        suite.expect(keys.key(for: .claude) == nil, "chat: no key to begin with")
        keys.setKey("  sk-ant-abc  ", for: .claude)
        suite.expect(keys.key(for: .claude) == "sk-ant-abc" && keys.key(for: .openai) == nil, "chat: a key is kept per service, trimmed")
        keys.setKey("", for: .claude)
        suite.expect(keys.key(for: .claude) == nil, "chat: saving nothing removes the key")

        let keyDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("nyx-chat-keys-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: keyDirectory) }
        let fileKeys = ChatFileKeyStore(directoryURL: keyDirectory)
        suite.expect(fileKeys.key(for: .claude) == nil, "chat: no key file, no key")
        suite.expect(fileKeys.setKey("  sk-ant-file-key-123  ", for: .claude) && fileKeys.setKey("nvapi-deep-key-456789", for: .nvidia),
                     "chat: keys are saved")
        suite.expect(ChatFileKeyStore(directoryURL: keyDirectory).key(for: .claude) == "sk-ant-file-key-123"
                        && ChatFileKeyStore(directoryURL: keyDirectory).key(for: .nvidia) == "nvapi-deep-key-456789"
                        && ChatFileKeyStore(directoryURL: keyDirectory).key(for: .openai) == nil,
                     "chat: keys are read back by a later launch, trimmed, one per service")
        let keyFile = keyDirectory.appendingPathComponent("Keys.json")
        let keyMode = (try? FileManager.default.attributesOfItem(atPath: keyFile.path))?[.posixPermissions] as? Int
        suite.expect(keyMode == 0o600, "chat: the key file is for its owner alone")
        fileKeys.setKey(nil, for: .claude)
        suite.expect(ChatFileKeyStore(directoryURL: keyDirectory).key(for: .claude) == nil
                        && ChatFileKeyStore(directoryURL: keyDirectory).key(for: .nvidia) != nil,
                     "chat: removing one key leaves the others")
        fileKeys.setKey("", for: .nvidia)
        suite.expect(!FileManager.default.fileExists(atPath: keyFile.path), "chat: with no keys left, the file is gone")
        suite.expect(!ChatFileKeyStore(directoryURL: nil).setKey("sk-nowhere-123456", for: .claude),
                     "chat: with no folder nothing is saved")

        func chat(_ title: String, age: TimeInterval, messages: Int = 1) -> ChatConversation {
            ChatConversation(title: title, provider: .claude, model: "m", createdAt: Date(timeIntervalSinceNow: -age),
                             updatedAt: Date(timeIntervalSinceNow: -age),
                             messages: (0..<messages).map { _ in ChatMessage(role: .user, text: title) })
        }
        let many = (0..<70).map { chat("c\($0)", age: TimeInterval($0)) } + [chat("empty", age: 0, messages: 0)]
        let kept = ChatHistoryRules.trimmed(many, limit: 25)
        suite.expect(kept.count == 25 && kept.first?.title == "c0" && !kept.contains { $0.title == "empty" },
                     "chat: history keeps the newest chats up to the limit and skips empty ones")
        suite.expect(ChatHistoryRules.clampedLimit(7) == ChatHistoryRules.defaultLimit && ChatHistoryRules.clampedLimit(100) == 100,
                     "chat: the limit is one of the offered values")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nyx-chat-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatHistoryStore(directoryURL: directory)
        suite.expect(store.load().isEmpty, "chat: no file is no history")
        var sample = chat("Hello", age: 5, messages: 0)
        var message = ChatMessage(role: .user, text: "Hi")
        message.context = "selected"
        sample.messages = [message, ChatMessage(role: .assistant, text: "Hello!")]
        suite.expect(store.save([sample]), "chat: history saves")
        let loaded = store.load()
        suite.expect(loaded.count == 1 && loaded[0].messages == sample.messages && loaded[0].title == "Hello",
                     "chat: history reads back as it was written")
        let file = directory.appendingPathComponent("Chats.json")
        let permissions = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int
        suite.expect(permissions == 0o600, "chat: the history file is for its owner alone")
        store.deleteAll()
        suite.expect(store.load().isEmpty && !FileManager.default.fileExists(atPath: file.path), "chat: deleting history removes the file")
        suite.expect(ChatHistoryStore(directoryURL: nil).load().isEmpty && !ChatHistoryStore(directoryURL: nil).save([sample]),
                     "chat: without a folder nothing is read or written")
    }

    // MARK: Wiring

    private static func wiring(_ suite: TestSuite) {
        suite.expect(AppFeature.notchChat.group == .dynamicIsland && AppFeature.notchChat.installedByDefault
                        && AppFeature.notchChat.permissions.isEmpty,
                     "chat: it is a Dynamic Island feature, installed, with no permission of its own")
        suite.expect(AppFeature.notchChat.rawValue == "notchChat", "chat: its feature id is stable")

        let shortcut = GlobalShortcutRole.chat.defaultShortcut
        suite.expect(shortcut == GlobalShortcut(keyCode: 49, modifiers: [.option, .shift]), "chat: Option-Shift-Space opens it")
        suite.expect(GlobalShortcutRole.chat.feature == .notchChat
                        && GlobalShortcutRole.chat.requiredEnableKeys.contains(DefaultsKey.notchChatShortcutEnabled)
                        && GlobalShortcutRole.chat.requiredEnableKeys.contains(DefaultsKey.notchEnabled),
                     "chat: its shortcut needs the island and its own switch")
        suite.expect(GlobalShortcutRole.conflict(for: .chatDefault, excluding: .chat, isOn: { _ in true }, isAvailable: { _ in true }) == nil,
                     "chat: its default does not clash with the command bar's Option-Space")

        let custom = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, cameraWidth: 210,
                                   layout: .custom, customWidth: 470, customHeight: 260)
        let plain = custom.expandedSize(module: .calendar)
        let regular = custom.expandedSize(module: .chat, chatSize: .regular)
        let large = custom.expandedSize(module: .chat, chatSize: .large)
        let huge = custom.expandedSize(module: .chat, chatSize: .huge)
        suite.expect(regular.height > plain.height && regular.width > plain.width
                        && large.height > regular.height && huge.height > large.height && large.width > regular.width,
                     "chat: its page is larger than the others on a custom island, and each size larger than the last")
        let tiny = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 640, height: 480), safeAreaTop: 32, cameraWidth: 210,
                                 layout: .custom, customWidth: 470, customHeight: 260)
        let capped = tiny.expandedSize(module: .chat, chatSize: .huge)
        suite.expect(capped.width <= 640 - 24 && capped.height <= 480 - 48,
                     "chat: even the largest size stays inside a small display")
        suite.expect(NotchChatSize.current(in: UserDefaults(suiteName: "com.nyx.tests.chat-size-none")!) == .large,
                     "chat: with no choice made the page is large")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchChatShortcutEnabled] as? Bool == false
                        && Defaults.registeredDefaults[DefaultsKey.notchChatSaveHistory] as? Bool == true
                        && Defaults.registeredDefaults[DefaultsKey.notchChatUseSelection] as? Bool == true,
                     "chat: the shortcut starts off, chats are kept, and the selection is used")
        suite.expect(Defaults.registeredDefaults.keys.allSatisfy { !$0.lowercased().contains("apikey") && !$0.lowercased().contains("chatkey") },
                     "chat: no key ever has a preference of its own")

        let keys = NotchModule.allCases.map(\.shortcutKey)
        suite.expect(Set(keys).count == keys.count && NotchModule.chat.shortcutKey == "h",
                     "chat: its page has its own direct key")
        suite.expect(NotchControlItem.defaultHidden.split(separator: ",").contains("chat"),
                     "chat: it is not among Home's small tiles unless asked for; it has a bar of its own")
        suite.expect(NotchControlItem.chat.module == .chat && NotchControlItem.chat.symbol == NotchModule.chat.symbol,
                     "chat: the Home button opens the chat page")

        let domain = "com.nyx.tests.chat-wiring"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        suite.expect(NotchSupport.modules(in: defaults).contains(.chat) && !NotchSupport.controls(in: defaults).contains(.chat),
                     "chat: a fresh setup has the page, and no small tile for it")
        // A saved layout with no room on the left gets its Chat bubble on the right, once.
        var saved = NotchQuickAccessConfiguration(buttons: [
            NotchQuickButton(id: UUID(), action: .explore, side: .left), NotchQuickButton(id: UUID(), action: .module(.agents), side: .left),
            NotchQuickButton(id: UUID(), action: .module(.timer), side: .left), NotchQuickButton(id: UUID(), action: .settings, side: .right),
        ])
        defaults.set(saved.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        Defaults.addChatQuickButtonOnce(in: defaults)
        let after = NotchQuickAccessConfiguration.stored(in: defaults)
        suite.expect(after.buttons.count == 5 && after.buttons.last?.action == .module(.chat) && after.buttons.last?.side == .right,
                     "chat: a saved layout gains a Chat bubble on the side that has room")
        Defaults.addChatQuickButtonOnce(in: defaults)
        suite.expect(NotchQuickAccessConfiguration.stored(in: defaults).buttons.count == 5, "chat: the bubble is added once")
        saved = after
        saved.buttons.removeAll { $0.action == .module(.chat) }
        defaults.set(saved.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        Defaults.addChatQuickButtonOnce(in: defaults)
        suite.expect(NotchQuickAccessConfiguration.stored(in: defaults).buttons.count == 4, "chat: removing the bubble sticks")
        defaults.removeObject(forKey: DefaultsKey.notchQuickAccessLayout)
        defaults.set(false, forKey: DefaultsKey.notchChatQuickButtonAdded)
        Defaults.addChatQuickButtonOnce(in: defaults)
        // A suite reads a default registered elsewhere in the process, which may be empty.
        suite.expect((defaults.data(forKey: DefaultsKey.notchQuickAccessLayout) ?? Data()).isEmpty,
                     "chat: with no saved layout the standard one is left as it is")
        defaults.set(false, forKey: DefaultsKey.notchChatEnabled)
        suite.expect(!NotchSupport.modules(in: defaults).contains(.chat),
                     "chat: switching it off removes the page")
        defaults.set(true, forKey: DefaultsKey.notchChatEnabled)
        defaults.set(false, forKey: AppFeature.notchChat.availabilityKey)
        suite.expect(!NotchSupport.modules(in: defaults).contains(.chat), "chat: uninstalling it removes the page")
        defaults.set(true, forKey: AppFeature.notchChat.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchSupport.routesChat(in: defaults), "chat: it cannot open while the island is off")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchSupport.routesChat(in: defaults), "chat: it opens once the island is on")
    }
}

private extension URLRequest {
    /// A request's body, which URLProtocol hands over as a stream.
    var bodyStreamData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
