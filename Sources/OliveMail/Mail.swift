import Foundation

struct MailboxInfo: Codable, Equatable, Sendable {
    var id: String
    var name: String
}

struct EmailSummary: Codable, Equatable, Sendable {
    var mailbox: String
    var id: String
    var from: String
    var to: String
    var date: String?
    var subject: String
}

struct EmailView: Codable, Equatable, Sendable {
    var mailbox: String
    var id: String
    var from: String
    var to: String
    var date: String
    var subject: String
    var body: String
}

// MVP: filters not implemented
// struct EmailFilter: Sendable {
//     var from: String?
//     var to: String?
//     var after: String?
//     var contains: String?
// }

protocol MailBackend: Sendable {
    // MVP: no multi-account; account stays commented
    // func listMailboxes(account: String?) async throws -> [MailboxInfo]
    func listMailboxes() async throws -> [MailboxInfo]
    func listEmails(mailbox: String?, limit: Int) async throws -> [EmailSummary]
    func showEmail(mailbox: String, id: String) async throws -> EmailView
}

func newestEmails(_ emails: [EmailSummary], limit: Int) -> [EmailSummary] {
    let formatter = ISO8601DateFormatter()
    func key(_ email: EmailSummary) -> Date {
        email.date.flatMap { formatter.date(from: $0) } ?? .distantPast
    }
    return Array(emails.sorted { key($0) > key($1) }.prefix(max(limit, 0)))
}

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(value)
    data.append(contentsOf: "\n".utf8)
    FileHandle.standardOutput.write(data)
}

func formatAddress(_ name: String?, email: String) -> String {
    if let name, !name.isEmpty {
        return "\(name) <\(email)>"
    }
    return email
}

func formatAddresses(_ addresses: [HimalayaAddress]) -> String {
    addresses.map { formatAddress($0.name, email: $0.email) }.joined(separator: ", ")
}
