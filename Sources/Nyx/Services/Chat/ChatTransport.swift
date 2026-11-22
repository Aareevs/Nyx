import Foundation

/// The two conversations with a service that need a connection: a reply and
/// the model list. Kept apart from the chat itself so they can be checked
/// against a stand-in server.
enum ChatTransport {
    /// Reads one reply, handing each piece of text to `onText` as it arrives.
    /// Answers nil when the reply ended as it should, or why it did not.
    /// Throws when the task is cancelled or the connection breaks.
    static func stream(_ request: URLRequest, provider: ChatProvider, session: URLSession,
                       onText: @MainActor (String) -> Void) async throws -> ChatFailure? {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { return .unreachable }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 20_000 { break }
            }
            return ChatAPI.failure(status: http.statusCode, message: ChatAPI.failureMessage(body: body))
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let event = ChatAPI.event(fromLine: line, provider: provider) else { continue }
            switch event {
            case .text(let piece): await onText(piece)
            case .done: return nil
            case .failed(let message): return ChatAPI.failure(status: 0, message: message)
            }
        }
        return nil
    }

    /// Whether `error` is the person stopping the reply rather than a fault.
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private enum Probe {
        case works, rejected, offline
        case failed(ChatFailure)
    }

    private static func probeOne(provider: ChatProvider, key: String, model: String, session: URLSession) async -> Probe {
        do {
            let (data, response) = try await session.data(for: ChatAPI.probeRequest(provider: provider, model: model, apiKey: key))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // A limit reached still shows the key is good and the model exists.
            if (200..<300).contains(status) || status == 429 { return .works }
            let failure = ChatAPI.failure(status: status, message: ChatAPI.failureMessage(body: data))
            return failure == .rejected ? .rejected : .failed(failure)
        } catch {
            if isCancellation(error) { return .failed(.unreachable) }
            return (error as? URLError)?.code == .notConnectedToInternet ? .offline : .failed(.unreachable)
        }
    }

    /// NVIDIA lists the same models to everyone, and most are not open to a given
    /// account: some answer "not found for account", some never answer. So a list
    /// that arrives proves nothing about the key or the models. Each is asked for
    /// one word, all at once, and the ones that reply are the account's models.
    /// A refused key ends it.
    static func sweep(provider: ChatProvider, key: String, models: [ChatModel],
                      session: URLSession) async -> Result<[ChatModel], ChatFailure> {
        let candidates = ChatAPI.probeCandidates(from: models)
        var working = Set<String>()
        var rejected = false
        var offline = false
        var last: ChatFailure = .api("No model answered")
        await withTaskGroup(of: (String, Probe).self) { group in
            for id in candidates {
                group.addTask { (id, await probeOne(provider: provider, key: key, model: id, session: session)) }
            }
            for await (id, outcome) in group {
                switch outcome {
                case .works: working.insert(id)
                case .rejected: rejected = true; group.cancelAll()
                case .offline: offline = true
                case .failed(let failure): last = failure
                }
            }
        }
        if rejected { return .failure(.rejected) }
        let usable = models.filter { working.contains($0.id) }
        let ordered = candidates.compactMap { id in usable.first { $0.id == id } }
        if ordered.isEmpty { return .failure(offline ? .unreachable : last) }
        return .success(ordered)
    }

    /// The models this key can use. Most services list exactly that; NVIDIA's
    /// list has to be tried model by model.
    static func availableModels(provider: ChatProvider, key: String, session: URLSession) async -> Result<[ChatModel], ChatFailure> {
        let listed = await models(provider: provider, key: key, session: session)
        guard provider == .nvidia, case .success(let list) = listed else { return listed }
        return await sweep(provider: provider, key: key, models: list, session: session)
    }

    static func models(provider: ChatProvider, key: String, session: URLSession) async -> Result<[ChatModel], ChatFailure> {
        do {
            let (data, response) = try await session.data(for: ChatAPI.modelsRequest(provider: provider, apiKey: key))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                return .failure(ChatAPI.failure(status: status, message: ChatAPI.failureMessage(body: data)))
            }
            return .success(ChatAPI.parseModels(data, provider: provider))
        } catch {
            return .failure(.unreachable)
        }
    }
}
