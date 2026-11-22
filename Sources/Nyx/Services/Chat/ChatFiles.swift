import AppKit
import Foundation
import PDFKit

/// A picture sent with a message, already shrunk and encoded for the services.
/// Kept in memory only: saved chats keep the file's name, not the picture.
struct ChatImage: Equatable {
    let mime: String
    let base64: String
}

/// A file the person added to the next message, read on this Mac. Text is
/// pulled out of documents here; pictures go to the service as pictures.
struct ChatPendingFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let symbol: String
    var text: String?
    var images: [ChatImage] = []
    var truncated = false
}

/// What a message remembers about a file once it is sent.
struct ChatFileInfo: Codable, Equatable {
    var name: String
    var symbol: String
    /// How many pictures this file sent; they are not saved, so a restored
    /// chat shows the name alone.
    var imageCount: Int?
}

enum ChatFileError: Error, Equatable {
    case unsupported(String)
    case tooLarge(String)
    case empty(String)
    case unreadable(String)

    var message: String {
        switch self {
        case .unsupported(let name): return "\(name) can't be read here. Use images, PDF, Word, Excel, CSV or text files."
        case .tooLarge(let name): return "\(name) is too large. The limit is 20 MB."
        case .empty(let name): return "No text or picture found in \(name)."
        case .unreadable(let name): return "Couldn't open \(name)."
        }
    }
}

enum ChatFileReader {
    static let maximumBytes = 20_000_000
    /// Text from all of a message's files together; a long book is cut here.
    static let maximumText = 60_000
    static let maximumImages = 4
    static let maximumPDFPages = 4
    static let imageEdge: CGFloat = 1568

    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "xml", "yaml", "yml", "log", "html", "htm", "css", "js", "ts",
        "swift", "py", "java", "c", "h", "cpp", "m", "go", "rs", "rb", "php", "sh", "sql", "toml", "ini", "rtf",
    ]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp"]
    static let wordExtensions: Set<String> = ["doc", "docx"]
    static let sheetExtensions: Set<String> = ["xlsx"]

    static var allExtensions: [String] {
        Array(textExtensions.union(imageExtensions).union(wordExtensions).union(sheetExtensions)) + ["pdf", "xls"]
    }

    static func read(_ url: URL) -> Result<ChatPendingFile, ChatFileError> {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maximumBytes else { return .failure(.tooLarge(name)) }

        if imageExtensions.contains(ext) {
            guard let data = try? Data(contentsOf: url), let image = encode(NSImage(data: data)) else {
                return .failure(.unreadable(name))
            }
            return .success(ChatPendingFile(name: name, symbol: "photo", images: [image]))
        }
        if ext == "pdf" { return pdf(url, name: name) }
        if wordExtensions.contains(ext) || ext == "rtf" {
            return text(from: wordText(url, ext: ext), name: name, symbol: "doc.text")
        }
        if ext == "xlsx" { return text(from: spreadsheetText(url), name: name, symbol: "tablecells") }
        if ext == "xls" { return .failure(.unsupported(name + " (old .xls)")) }
        if textExtensions.contains(ext) || ext.isEmpty {
            guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable(name)) }
            let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            return text(from: string, name: name, symbol: ext == "csv" || ext == "tsv" ? "tablecells" : "doc.plaintext")
        }
        return .failure(.unsupported(name))
    }

    // MARK: Text

    private static func text(from string: String?, name: String, symbol: String) -> Result<ChatPendingFile, ChatFileError> {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return .failure(.empty(name)) }
        let cut = trimmed.count > maximumText
        return .success(ChatPendingFile(name: name, symbol: symbol, text: String(trimmed.prefix(maximumText)), truncated: cut))
    }

    private static func wordText(_ url: URL, ext: String) -> String? {
        let type: NSAttributedString.DocumentType = ext == "docx" ? .officeOpenXML : ext == "rtf" ? .rtf : .docFormat
        return (try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil))?.string
    }

    // MARK: PDF

    private static func pdf(_ url: URL, name: String) -> Result<ChatPendingFile, ChatFileError> {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return .failure(.unreadable(name)) }
        let extracted = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !extracted.isEmpty { return text(from: extracted, name: name, symbol: "doc.richtext") }
        // A scan has no text to read: its first pages go as pictures instead,
        // for the service to read.
        var images: [ChatImage] = []
        for index in 0..<min(document.pageCount, maximumPDFPages) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(2, imageEdge / max(bounds.width, bounds.height))
            let thumbnail = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            if let image = encode(thumbnail) { images.append(image) }
        }
        guard !images.isEmpty else { return .failure(.empty(name)) }
        return .success(ChatPendingFile(name: name, symbol: "doc.richtext", images: images,
                                        truncated: document.pageCount > maximumPDFPages))
    }

    // MARK: Spreadsheets

    /// The sheets of an .xlsx as tab-separated rows. An .xlsx is a zip of
    /// XML files; the system's unzip hands them over one at a time.
    private static func spreadsheetText(_ url: URL) -> String? {
        guard let names = unzip(url, "xl/workbook.xml").flatMap({ sheetNames(in: $0) }) else { return nil }
        let shared = unzip(url, "xl/sharedStrings.xml").map(sharedStrings(in:)) ?? []
        var output: [String] = []
        for (index, name) in names.enumerated() {
            guard let sheet = unzip(url, "xl/worksheets/sheet\(index + 1).xml") else { continue }
            output.append("Sheet: \(name)\n" + rows(in: sheet, shared: shared).joined(separator: "\n"))
        }
        return output.isEmpty ? nil : output.joined(separator: "\n\n")
    }

    private static func unzip(_ url: URL, _ member: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, member]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    static func sheetNames(in workbook: String) -> [String] {
        matches(#"<sheet [^>]*name="([^"]*)""#, in: workbook).map { unescape($0[1]) }
    }

    static func sharedStrings(in xml: String) -> [String] {
        matches(#"<si>(.*?)</si>"#, in: xml).map { item in
            matches(#"<t[^>]*>(.*?)</t>"#, in: item[1]).map { unescape($0[1]) }.joined()
        }
    }

    static func rows(in sheet: String, shared: [String]) -> [String] {
        matches(#"<row[^>]*>(.*?)</row>"#, in: sheet).map { row in
            matches(#"<c ([^>]*?)(?:/>|>(.*?)</c>)"#, in: row[1]).map { cell in
                let attributes = cell[1], body = cell[2]
                let value = matches(#"<v>(.*?)</v>"#, in: body).first?[1]
                    ?? matches(#"<t[^>]*>(.*?)</t>"#, in: body).first?[1] ?? ""
                if attributes.contains(#"t="s""#), let index = Int(value), shared.indices.contains(index) {
                    return shared[index]
                }
                return unescape(value)
            }.joined(separator: "\t")
        }
    }

    private static func unescape(_ text: String) -> String {
        var result = text
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    // MARK: Pictures

    /// A JPEG no wider than the services take, as base64. Nil when the
    /// picture cannot be read.
    static func encode(_ image: NSImage?) -> ChatImage? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, imageEdge / max(image.size.width, image.size.height))
        let width = max(1, Int(image.size.width * scale)), height = max(1, Int(image.size.height * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // A transparent picture goes onto white, which JPEG would make black.
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return nil }
        return ChatImage(mime: "image/jpeg", base64: data.base64EncodedString())
    }
}
