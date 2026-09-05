import Foundation
import Testing
#if canImport(System)
import System
#else
import SystemPackage
#endif
@testable import OliveMail

@Test func newestEmailsCutsAndSorts() {
    let emails = [
        EmailSummary(mailbox: "INBOX", id: "1", from: "a", to: "b", date: "2026-01-01T00:00:00Z", subject: "old"),
        EmailSummary(mailbox: "Sent", id: "2", from: "a", to: "b", date: "2026-06-01T00:00:00Z", subject: "new"),
        EmailSummary(mailbox: "INBOX", id: "3", from: "a", to: "b", date: "2026-03-01T00:00:00Z", subject: "mid"),
    ]
    let top = newestEmails(emails, limit: 2)
    #expect(top.map(\.id) == ["2", "3"])
}

@Test func himalayaBackendListsAndShows() async throws {
    let paths = Paths(directory: FilePath("/tmp/olive-mail-test"))
    let backend = HimalayaBackend(paths: paths) { args in
        switch args.first {
        case "mailbox":
            return Data(#"{"mailboxes":[{"id":"INBOX","name":"Inbox"},{"id":"Sent","name":"Sent"}]}"#.utf8)
        case "envelope":
            let mailbox = args[args.firstIndex(of: "-m")! + 1]
            if mailbox == "INBOX" {
                return Data(#"{"envelopes":[{"id":"10","subject":"Hello","from":[{"name":"Alice","email":"alice@example.com"}],"to":[{"name":null,"email":"you@example.com"}],"date":"2026-06-01T12:00:00Z"}]}"#.utf8)
            }
            return Data(#"{"envelopes":[{"id":"20","subject":"Sent mail","from":[{"email":"you@example.com"}],"to":[{"email":"alice@example.com"}],"date":"2026-05-01T12:00:00Z"}]}"#.utf8)
        case "message":
            return Data(#"""
            {"html_body":[0],"text_body":[0],"attachments":[],"parts":[{"headers":[{"name":"from","value":{"Address":{"List":[{"name":"Alice","address":"alice@example.com"}]}}},{"name":"to","value":{"Address":{"List":[{"name":"Bob","address":"bob@example.com"}]}}},{"name":"date","value":{"DateTime":{"year":2025,"month":7,"day":24,"hour":10,"minute":0,"second":0,"tz_before_gmt":false,"tz_hour":0,"tz_minute":0}}},{"name":"subject","value":{"Text":"Hello invoice"}}],"body":{"Text":"Hi Bob,\nthis is the body.\n"}}]}
            """#.utf8)
        default:
            throw OliveMailError.himalayaFailed("unexpected \(args)")
        }
    }

    let boxes = try await backend.listMailboxes()
    #expect(boxes.map(\.id) == ["INBOX", "Sent"])

    let inbox = try await backend.listEmails(mailbox: "INBOX", limit: 20)
    #expect(inbox.count == 1)
    #expect(inbox[0].id == "10")
    #expect(inbox[0].mailbox == "INBOX")
    #expect(inbox[0].from == "Alice <alice@example.com>")

    let merged = try await backend.listEmails(mailbox: nil, limit: 20)
    #expect(merged.map(\.id) == ["10", "20"])

    let limited = try await backend.listEmails(mailbox: nil, limit: 1)
    #expect(limited.map(\.id) == ["10"])

    let view = try await backend.showEmail(mailbox: "INBOX", id: "10")
    #expect(view.from == "Alice <alice@example.com>")
    #expect(view.to == "Bob <bob@example.com>")
    #expect(view.subject == "Hello invoice")
    #expect(view.date == "2025-07-24T10:00:00Z")
    #expect(view.body.contains("Hi Bob"))
}

@Test func unknownFolderIsEmptyList() async throws {
    let paths = Paths(directory: FilePath("/tmp/olive-mail-test"))
    let backend = HimalayaBackend(paths: paths) { _ in
        throw OliveMailError.himalayaFailed("IMAP SELECT failed: NO unknown folder")
    }
    let emails = try await backend.listEmails(mailbox: "INBOX", limit: 20)
    #expect(emails.isEmpty)
}

@Test func emptyMailboxIsEmptyList() async throws {
    let paths = Paths(directory: FilePath("/tmp/olive-mail-test"))
    let backend = HimalayaBackend(paths: paths) { _ in
        throw OliveMailError.himalayaFailed("cannot list imap envelopes: page 1 out of bounds")
    }
    let emails = try await backend.listEmails(mailbox: "INBOX", limit: 20)
    #expect(emails.isEmpty)
}

@Test func himalayaMissingOnEmptyPath() {
    #expect(Himalaya.findExecutable("himalaya", path: "", extra: []) == nil)
}
