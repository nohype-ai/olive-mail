import Foundation
#if canImport(System)
import System
#else
import SystemPackage
#endif

struct HimalayaAddress: Decodable, Equatable, Sendable {
    var email: String
    var name: String?
}

struct HimalayaBackend: MailBackend {
    let paths: Paths
    let invoke: @Sendable ([String]) async throws -> Data

    init(
        paths: Paths,
        invoke: (@Sendable ([String]) async throws -> Data)? = nil
    ) {
        self.paths = paths
        let config = paths.himalayaConfig
        self.invoke = invoke ?? { args in
            try await Himalaya.run(config: config, arguments: args)
        }
    }

    func listMailboxes() async throws -> [MailboxInfo] {
        let data = try await invoke(["mailbox", "list"])
        let decoded = try decode(HimalayaMailboxes.self, from: data)
        return decoded.mailboxes.map { MailboxInfo(id: $0.id, name: $0.name) }
    }

    func listEmails(mailbox: String?, limit: Int) async throws -> [EmailSummary] {
        if let mailbox {
            return try await envelopes(mailbox: mailbox, limit: limit)
        }
        let boxes = try await listMailboxes()
        var all: [EmailSummary] = []
        for box in boxes {
            all.append(contentsOf: try await envelopes(mailbox: box.id, limit: limit))
        }
        return newestEmails(all, limit: limit)
    }

    func showEmail(mailbox: String, id: String) async throws -> EmailView {
        let data = try await invoke(["message", "read", "-m", mailbox, id])
        return try HimalayaMessage.parse(data, mailbox: mailbox, id: id)
    }

    private func envelopes(mailbox: String, limit: Int) async throws -> [EmailSummary] {
        let data: Data
        do {
            data = try await invoke([
                "envelope", "list",
                "-m", mailbox,
                "--page-size", String(max(limit, 1)),
                "--page", "1",
            ])
        } catch let error as OliveMailError {
            if case .himalayaFailed(let message) = error, isSkippableMailboxError(message) {
                return []
            }
            throw error
        }
        let decoded = try decode(HimalayaEnvelopes.self, from: data)
        return decoded.envelopes.map { envelope in
            EmailSummary(
                mailbox: mailbox,
                id: envelope.id,
                from: formatAddresses(envelope.from ?? []),
                to: formatAddresses(envelope.to ?? []),
                date: envelope.date,
                subject: envelope.subject ?? ""
            )
        }
    }
}

enum Himalaya {
    static func run(config: FilePath, arguments: [String]) async throws -> Data {
        guard let binary = findExecutable("himalaya") else {
            throw OliveMailError.missingHimalaya
        }
        return try await run(
            executable: binary,
            arguments: ["-c", config.string, "--json"] + arguments
        )
    }

    static func findExecutable(
        _ name: String,
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        extra: [String] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/home/linuxbrew/.linuxbrew/bin",
        ]
    ) -> FilePath? {
        var dirs: [String] = []
        if let path {
            dirs.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        dirs.append(contentsOf: extra)
        let fm = FileManager.default
        var seen = Set<String>()
        for dir in dirs where seen.insert(dir).inserted {
            let candidate = FilePath(dir).appending(name)
            if fm.isExecutableFile(atPath: candidate.string) {
                return candidate
            }
        }
        return nil
    }

    private static func run(executable: FilePath, arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable.string)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outTask = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }
        let errTask = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
        process.waitUntilExit()
        let out = await outTask.value
        let err = await errTask.value
        if !err.isEmpty {
            FileHandle.standardError.write(err)
        }
        if process.terminationStatus != 0 {
            if let payload = try? JSONDecoder().decode(HimalayaErrorPayload.self, from: out) {
                throw OliveMailError.himalayaFailed(payload.error)
            }
            let message = String(data: err.isEmpty ? out : err, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw OliveMailError.himalayaFailed(
                message?.isEmpty == false ? message! : "himalaya exited \(process.terminationStatus)"
            )
        }
        return out
    }
}

private struct HimalayaMailboxes: Decodable {
    var mailboxes: [HimalayaMailbox]
}

private struct HimalayaMailbox: Decodable {
    var id: String
    var name: String
}

private struct HimalayaEnvelopes: Decodable {
    var envelopes: [HimalayaEnvelope]
}

private struct HimalayaEnvelope: Decodable {
    var id: String
    var subject: String?
    var from: [HimalayaAddress]?
    var to: [HimalayaAddress]?
    var date: String?
}

private struct HimalayaErrorPayload: Decodable {
    var error: String
}

private func isSkippableMailboxError(_ message: String) -> Bool {
    let text = message.lowercased()
    return text.contains("out of bounds")
        || text.contains("unknown folder")
        || text.contains("does not exist")
        || text.contains("noselect")
}

private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    if let payload = try? JSONDecoder().decode(HimalayaErrorPayload.self, from: data),
       !payload.error.isEmpty {
        throw OliveMailError.himalayaFailed(payload.error)
    }
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw OliveMailError.himalayaJSON(error.localizedDescription)
    }
}

enum HimalayaMessage {
    static func parse(_ data: Data, mailbox: String, id: String) throws -> EmailView {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw OliveMailError.himalayaJSON(error.localizedDescription)
        }
        if let string = object as? String {
            return parseHuman(string, mailbox: mailbox, id: id)
        }
        guard let root = object as? [String: Any] else {
            throw OliveMailError.himalayaJSON("expected object")
        }
        if let error = root["error"] as? String {
            throw OliveMailError.himalayaFailed(error)
        }
        let parts = root["parts"] as? [[String: Any]] ?? []
        var from = ""
        var to = ""
        var date = ""
        var subject = ""
        if let headers = parts.first?["headers"] as? [[String: Any]] {
            for header in headers {
                switch (header["name"] as? String)?.lowercased() {
                case "from": from = formatHeaderAddress(header["value"])
                case "to": to = formatHeaderAddress(header["value"])
                case "subject": subject = headerText(header["value"])
                case "date": date = headerDate(header["value"])
                default: break
                }
            }
        }
        let body = extractBody(root: root, parts: parts)
        return EmailView(
            mailbox: mailbox,
            id: id,
            from: from,
            to: to,
            date: date,
            subject: subject,
            body: body
        )
    }

    private static func extractBody(root: [String: Any], parts: [[String: Any]]) -> String {
        func body(at index: Int) -> String? {
            guard parts.indices.contains(index) else { return nil }
            let text = partText(parts[index])
            return text.isEmpty ? nil : text
        }
        if let indexes = intArray(root["text_body"]) {
            for index in indexes {
                if let text = body(at: index) { return text }
            }
        }
        if let indexes = intArray(root["html_body"]) {
            for index in indexes {
                if let text = body(at: index) { return text }
            }
        }
        for part in parts {
            let text = partText(part)
            if !text.isEmpty { return text }
        }
        return ""
    }

    private static func partText(_ part: [String: Any]) -> String {
        guard let body = part["body"] as? [String: Any] else { return "" }
        if let text = body["Text"] as? String { return text }
        if let html = body["Html"] as? String { return html }
        return ""
    }

    private static func formatHeaderAddress(_ value: Any?) -> String {
        guard let value = value as? [String: Any],
              let address = value["Address"] as? [String: Any] else {
            return headerText(value)
        }
        let list: [[String: Any]]
        if let items = address["List"] as? [[String: Any]] {
            list = items
        } else if let groups = address["Group"] as? [[String: Any]] {
            list = groups.flatMap { $0["addresses"] as? [[String: Any]] ?? [] }
        } else {
            return headerText(value)
        }
        return list.map { item in
            let email = item["address"] as? String ?? item["email"] as? String ?? ""
            return formatAddress(item["name"] as? String, email: email)
        }.joined(separator: ", ")
    }

    private static func headerText(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let object = value as? [String: Any], let text = object["Text"] as? String {
            return text
        }
        return ""
    }

    private static func headerDate(_ value: Any?) -> String {
        let text = headerText(value)
        if !text.isEmpty { return text }
        guard let object = value as? [String: Any],
              let dt = object["DateTime"] as? [String: Any],
              let year = intValue(dt["year"]),
              let month = intValue(dt["month"]),
              let day = intValue(dt["day"]) else {
            return ""
        }
        let hour = intValue(dt["hour"]) ?? 0
        let minute = intValue(dt["minute"]) ?? 0
        let second = intValue(dt["second"]) ?? 0
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", year, month, day, hour, minute, second)
    }

    private static func parseHuman(_ text: String, mailbox: String, id: String) -> EmailView {
        var from = ""
        var to = ""
        var date = ""
        var subject = ""
        var bodyLines: [String] = []
        var inBody = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if !inBody {
                if line.hasPrefix("From: ") { from = String(line.dropFirst(6)) }
                else if line.hasPrefix("To: ") { to = String(line.dropFirst(4)) }
                else if line.hasPrefix("Date: ") { date = String(line.dropFirst(6)) }
                else if line.hasPrefix("Subject: ") { subject = String(line.dropFirst(9)) }
                else if line.isEmpty { inBody = true }
            } else {
                bodyLines.append(line)
            }
        }
        return EmailView(
            mailbox: mailbox,
            id: id,
            from: from,
            to: to,
            date: date,
            subject: subject,
            body: bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func intArray(_ value: Any?) -> [Int]? {
        if let ints = value as? [Int] { return ints }
        if let numbers = value as? [NSNumber] { return numbers.map(\.intValue) }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
