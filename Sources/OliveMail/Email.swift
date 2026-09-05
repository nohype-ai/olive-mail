import ArgumentParser

struct Email: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Emails.",
        subcommands: [List.self, Search.self, Show.self]
    )

    struct Options: ParsableArguments {
        @OptionGroup var globals: Globals

        @Option(name: .shortAndLong, help: "Mailbox.")
        var mailbox: String?
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List emails in a mailbox."
        )

        @OptionGroup var options: Options

        mutating func run() async throws {}
    }

    struct Search: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Search emails in a mailbox."
        )

        @OptionGroup var options: Options

        @Argument(help: "Query terms, e.g. from alice@client.com after 2026-01-01.")
        var query: [String] = []

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

        @Argument(help: "IMAP location id in that mailbox.")
        var id: String

        @Argument(help: "Only these fields (from, to, subject, date, body).")
        var fields: [Field] = []

        mutating func run() async throws {}
    }
}