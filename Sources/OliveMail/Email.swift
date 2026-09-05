import ArgumentParser

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

        @Option(help: "From address.")
        var from: String?

        @Option(help: "To address.")
        var to: String?

        @Option(help: "Only emails after this date (YYYY-MM-DD).")
        var after: String?

        @Option(help: "Match this text.")
        var contains: String?

        @Option(help: "Maximum emails to list.")
        var limit: Int = 20

        mutating func run() async throws {}
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show one email."
        )

        enum Field: String, ExpressibleByArgument, CaseIterable {
            case from, to, subject, date, body
        }

        @OptionGroup var options: Options

        @Argument(help: "Location id.")
        var id: String

        @Argument(help: "Only these fields (from, to, subject, date, body).")
        var fields: [Field] = []

        mutating func run() async throws {}
    }
}