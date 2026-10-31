import Foundation
import SQLite3

/// Gemini CLI keeps each session as one JSON file,
/// `~/.gemini/tmp/<project hash>/chats/session-*.json`, rewritten as the
/// session goes on. Only each reply's model, time and token counts are read;
/// what was said is never looked at.
enum AgentGeminiSessions {
    /// A session larger than this is not read.
    static let maximumSize: UInt64 = 64 << 20

    static func isSession(_ path: String) -> Bool {
        (path.hasSuffix(".json") && path.contains("/chats/") && (path as NSString).lastPathComponent.hasPrefix("session-"))
            || isAntigravity(path)
    }

    /// Antigravity keeps each conversation as a SQLite file.
    static func isAntigravity(_ path: String) -> Bool {
        path.hasSuffix(".db") && path.contains("/conversations/") && path.contains("/.gemini/")
    }

    /// Every session file under the folder that holds the project folders, or
    /// Antigravity's conversation databases when the folder is theirs.
    static func files(in root: URL) -> [URL] {
        let manager = FileManager.default
        if root.lastPathComponent == "conversations" {
            let names = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles])) ?? []
            return names.filter { isAntigravity($0.path) }
        }
        let projects = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles])) ?? []
        var found: [URL] = []
        for project in projects {
            let chats = project.appending(path: "chats", directoryHint: .isDirectory)
            let names = (try? manager.contentsOfDirectory(at: chats, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles])) ?? []
            found += names.filter { isSession($0.path) }
        }
        return found
    }

    /// Hands over one small JSON payload per reply that reported tokens. A
    /// reply read again counts once, because its id is its key. The offset
    /// only records the size read, so a changed file is read again; a file
    /// caught mid-write is left until it parses.
    static func readAppended(_ cursor: AgentLogCursor, line: (Data) -> Void) {
        if isAntigravity(cursor.path) {
            readAntigravity(cursor, line: line)
            return
        }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let size = UInt64(max(0, info.st_size))
        cursor.identity = UInt64(info.st_ino)
        cursor.modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                                + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        guard size != cursor.offset else { return }
        guard size <= maximumSize,
              let data = try? Data(contentsOf: URL(fileURLWithPath: cursor.path)),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return }
        let session = root["sessionId"] as? String ?? ""
        let project = root["projectHash"] as? String ?? ""
        for message in messages where message["type"] as? String == "gemini" {
            guard let id = message["id"] as? String, let tokens = message["tokens"] as? [String: Any] else { continue }
            let payload: [String: Any] = ["gemini": true, "id": id, "ts": message["timestamp"] ?? "",
                                          "model": message["model"] ?? "", "tokens": tokens,
                                          "session": session, "project": project]
            if let encoded = try? JSONSerialization.data(withJSONObject: payload) { line(encoded) }
        }
        cursor.offset = size
    }

    // MARK: - Antigravity

    /// One model call per row of `gen_metadata`, a protobuf message. Only the
    /// token counts, the model name and the time are decoded, by the numbers
    /// the fields carry; text is never read. The cursor's offset is the next
    /// row to read.
    private static func readAntigravity(_ cursor: AgentLogCursor, line: (Data) -> Void) {
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        cursor.identity = UInt64(info.st_ino)
        var wal = stat()
        let walTime = stat(cursor.path + "-wal", &wal) == 0 ? wal.st_mtimespec : info.st_mtimespec
        let newest = max(info.st_mtimespec.tv_sec, walTime.tv_sec)
        cursor.modified = Date(timeIntervalSince1970: TimeInterval(newest))
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT idx, data FROM gen_metadata WHERE idx >= ? ORDER BY idx"
        // A database Antigravity is not using has no write-ahead index file, and
        // SQLite cannot open that read-only: it is read as an unchanging file.
        func prepare(_ uri: String) -> Bool {
            sqlite3_finalize(statement)
            statement = nil
            sqlite3_close(db)
            db = nil
            guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return false }
            sqlite3_busy_timeout(db, 1500)
            return sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK
        }
        let escaped = cursor.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cursor.path
        guard prepare("file:\(escaped)?mode=ro") || prepare("file:\(escaped)?immutable=1") else { return }
        sqlite3_bind_int64(statement, 1, Int64(cursor.offset))
        let conversation = ((cursor.path as NSString).lastPathComponent as NSString).deletingPathExtension
        // Every step carries a status, 3 once it is done. A few old steps stay
        // in other states for good (6 and 7 are the ones seen), so only the
        // rest count as the agent being at work. Between two steps nothing is
        // running for a moment while the file is still being written, so a
        // write in the last few seconds counts as work as well. Once all of
        // that is quiet, the task is over.
        var steps: OpaquePointer?
        defer { sqlite3_finalize(steps) }
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM steps WHERE status NOT IN (3, 6, 7)", -1, &steps, nil) == SQLITE_OK,
           sqlite3_step(steps) == SQLITE_ROW {
            let running = sqlite3_column_int64(steps, 0) > 0
            let quiet = Date().timeIntervalSince1970 - cursor.modified.timeIntervalSince1970
            // Settings can switch the working mark off for good, whatever the file says.
            let shows = UserDefaults.standard.object(forKey: DefaultsKey.notchAgentsGeminiLive) as? Bool ?? true
            let working = shows && ((running && quiet < 90) || quiet < 15)
            let state: [String: Any] = ["gemini": true, "phase": working ? "active" : "idle",
                                        "ts": cursor.modified.timeIntervalSince1970, "session": conversation]
            if let encoded = try? JSONSerialization.data(withJSONObject: state) { line(encoded) }
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            let index = sqlite3_column_int64(statement, 0)
            cursor.offset = UInt64(index) + 1
            guard let bytes = sqlite3_column_blob(statement, 1) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            guard let call = decodeCall(data) else { continue }
            let payload: [String: Any] = [
                "gemini": true, "id": "agy:\(conversation):\(index)", "ts": call.time, "model": call.model,
                "tokens": ["input": call.input + call.cacheRead, "cached": call.cacheRead,
                           "output": max(0, call.output - call.thoughts), "thoughts": call.thoughts],
                "session": conversation, "projectName": "Antigravity"]
            if let encoded = try? JSONSerialization.data(withJSONObject: payload) { line(encoded) }
        }
    }

    private struct Call {
        var input = 0, output = 0, cacheRead = 0, thoughts = 0
        var model = ""
        var time = 0.0
    }

    /// The numbered fields of the call record, found by comparing rows: field 4
    /// holds the counts (2 input not served from cache, 3 output, 5 read from
    /// cache, 9 of the output spent thinking), 19 the model, 9.4.1 the time.
    private static func decodeCall(_ data: Data) -> Call? {
        guard let record = Proto.fields(data).first(where: { $0.number == 1 && $0.bytes != nil })?.bytes else { return nil }
        let fields = Proto.fields(record)
        var call = Call()
        if let counts = fields.first(where: { $0.number == 4 })?.bytes.map(Proto.fields) {
            func number(_ n: Int) -> Int { Int(counts.first { $0.number == n && $0.bytes == nil }?.varint ?? 0) }
            call.input = number(2)
            call.output = number(3)
            call.cacheRead = number(5)
            call.thoughts = min(number(9), call.output)
        }
        if let name = fields.first(where: { $0.number == 19 })?.bytes { call.model = String(decoding: name, as: UTF8.self) }
        if let stamp = fields.first(where: { $0.number == 9 })?.bytes.map(Proto.fields),
           let moment = stamp.first(where: { $0.number == 4 })?.bytes.map(Proto.fields),
           let seconds = moment.first(where: { $0.number == 1 })?.varint {
            call.time = TimeInterval(seconds)
        }
        guard call.input + call.output + call.cacheRead > 0, call.time > 0, !call.model.isEmpty else { return nil }
        return call
    }
}

/// Just enough of the protobuf wire format to read numbered fields.
enum Proto {
    struct Field {
        let number: Int
        let varint: UInt64
        /// The payload of a length-delimited field; nil for numbers.
        let bytes: Data?
    }

    static func fields(_ data: Data) -> [Field] {
        var result: [Field] = []
        var position = data.startIndex
        func varint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while position < data.endIndex, shift < 64 {
                let byte = data[position]
                position += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }
        while position < data.endIndex {
            guard let key = varint() else { break }
            let number = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let value = varint() else { return result }
                result.append(Field(number: number, varint: value, bytes: nil))
            case 1:
                guard data.endIndex - position >= 8 else { return result }
                position += 8
            case 2:
                guard let length = varint(), length <= UInt64(data.endIndex - position) else { return result }
                let end = position + Int(length)
                result.append(Field(number: number, varint: 0, bytes: data[position..<end]))
                position = end
            case 5:
                guard data.endIndex - position >= 4 else { return result }
                position += 4
            default:
                return result
            }
        }
        return result
    }
}
