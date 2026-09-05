import Foundation

extension HimalayaBackend {
    func listEmails(mailbox: String?, limit: Int) async throws -> [Email.Summary] {
        if let mailbox {
            return try await envelopes(mailbox: mailbox, limit: limit)
        }
        let boxes = try await listMailboxes()
        var all: [Email.Summary] = []
        for box in boxes {
            all.append(contentsOf: try await envelopes(mailbox: box.id, limit: limit))
        }
        return newestEmails(all, limit: limit)
    }

    private func envelopes(mailbox: String, limit: Int) async throws -> [Email.Summary] {
        let data: Data
        do {
            data = try await invoke([
                "envelope", "list",
                "-m", mailbox,
                "--page-size", String(max(limit, 1)),
                "--page", "1",
            ])
        } catch let error as OliveMailError {
            if case .himalayaFailed(let message) = error, isUnreadableMailbox(message) {
                return []
            }
            throw error
        }
        let decoded = try Himalaya.decode(EnvelopeList.self, from: data)
        return decoded.envelopes.map { envelope in
            Email.Summary(
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

private struct EnvelopeList: Decodable {
    var envelopes: [Envelope]
}

private struct Envelope: Decodable {
    var id: String
    var subject: String?
    var from: [Address]?
    var to: [Address]?
    var date: String?
}

private struct Address: Decodable {
    var email: String
    var name: String?
}

private func formatAddresses(_ addresses: [Address]) -> String {
    addresses.map { formatAddress($0.name, email: $0.email) }.joined(separator: ", ")
}

private func isUnreadableMailbox(_ message: String) -> Bool {
    let text = message.lowercased()
    return text.contains("out of bounds")
        || text.contains("unknown folder")
        || text.contains("does not exist")
        || text.contains("noselect")
}
