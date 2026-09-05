import ArgumentParser
import Foundation

struct Email: AsyncParsableCommand {
    struct Summary: Codable, Equatable, Sendable {
        var mailbox: String
        var id: String
        var from: String
        var to: String
        var date: String?
        var subject: String
    }

    struct View: Codable, Equatable, Sendable {
        var mailbox: String
        var id: String
        var from: String
        var to: String
        var date: String
        var subject: String
        var body: String
    }

    static let configuration = CommandConfiguration(
        abstract: "Emails.",
        subcommands: [List.self, Show.self]
    )

    struct Options: ParsableArguments {
        @OptionGroup var globals: Globals

        @Option(name: .shortAndLong, help: "Mailbox. Omitted: all mailboxes.")
        var mailbox: String?
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List emails."
        )

        @OptionGroup var options: Options

        // MVP: filters not implemented
        // @Option(help: "From address.")
        // var from: String?
        //
        // @Option(help: "To address.")
        // var to: String?
        //
        // @Option(help: "Only emails after this date (YYYY-MM-DD).")
        // var after: String?
        //
        // @Option(help: "Match this text.")
        // var contains: String?

        @Option(help: "Maximum emails to list.")
        var limit: Int = 20

        mutating func run() async throws {
            let paths = try FilePaths.resolve()
            try paths.requireConfigured()
            let backend = HimalayaBackend(paths: paths)
            let emails = try await backend.listEmails(
                mailbox: options.mailbox,
                limit: limit
            )
            if options.globals.json {
                try printJSON(["emails": emails])
            } else {
                for email in emails {
                    print(
                        [
                            email.mailbox,
                            email.id,
                            email.from,
                            email.to,
                            email.date ?? "",
                            email.subject,
                        ].joined(separator: "\t")
                    )
                }
            }
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show one email."
        )

        enum Field: String, ExpressibleByArgument, CaseIterable {
            case from, to, subject, date, body
        }

        @OptionGroup var globals: Globals

        @Option(name: .shortAndLong, help: "Mailbox.")
        var mailbox: String

        @Argument(help: "Location id.")
        var id: String

        @Argument(help: "Only these fields (from, to, subject, date, body).")
        var fields: [Field] = []

        mutating func run() async throws {
            let paths = try FilePaths.resolve()
            try paths.requireConfigured()
            let backend = HimalayaBackend(paths: paths)
            let view = try await backend.showEmail(mailbox: mailbox, id: id)
            let wanted = fields.isEmpty ? Field.allCases : fields
            if globals.json {
                try printJSON(jsonObject(view, fields: wanted))
            } else {
                print(human(view, fields: wanted))
            }
        }

        private func jsonObject(_ view: View, fields: [Field]) -> [String: String] {
            var object: [String: String] = [
                "mailbox": view.mailbox,
                "id": view.id,
            ]
            for field in fields {
                switch field {
                case .from: object["from"] = view.from
                case .to: object["to"] = view.to
                case .subject: object["subject"] = view.subject
                case .date: object["date"] = view.date
                case .body: object["body"] = view.body
                }
            }
            return object
        }

        private func human(_ view: View, fields: [Field]) -> String {
            fields.map { field in
                switch field {
                case .from: "From: \(view.from)"
                case .to: "To: \(view.to)"
                case .subject: "Subject: \(view.subject)"
                case .date: "Date: \(view.date)"
                case .body: view.body
                }
            }.joined(separator: "\n")
        }
    }
}

func newestEmails(_ emails: [Email.Summary], limit: Int) -> [Email.Summary] {
    let formatter = ISO8601DateFormatter()
    func key(_ email: Email.Summary) -> Date {
        email.date.flatMap { formatter.date(from: $0) } ?? .distantPast
    }
    return Array(emails.sorted { key($0) > key($1) }.prefix(max(limit, 0)))
}

func formatAddress(_ name: String?, email: String) -> String {
    if let name, !name.isEmpty {
        return "\(name) <\(email)>"
    }
    return email
}
