import ArgumentParser
import Foundation

struct Email: AsyncParsableCommand {
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
            let paths = try Paths.resolve()
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
            let paths = try Paths.resolve()
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

        private func jsonObject(_ view: EmailView, fields: [Field]) -> [String: String] {
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

        private func human(_ view: EmailView, fields: [Field]) -> String {
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
