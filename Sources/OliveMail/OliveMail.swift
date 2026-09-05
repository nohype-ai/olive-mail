import ArgumentParser

@main
struct OliveMail: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Real email context for agents.",
        subcommands: [Auth.self, Mailbox.self, List.self, Search.self, Show.self]
    )
}

struct Globals: ParsableArguments {
    @Option(name: .shortAndLong, help: "Email account.")
    var account: String?

    @Flag(help: "JSON output.")
    var json = false
}

struct Auth: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Store IMAP credentials for an account."
    )

    @Argument(help: "Email address.")
    var email: String?

    @Option(help: "IMAP server URL (e.g. imaps://imap.example.com:993).")
    var imap: String?

    mutating func run() async throws {}
}

struct Mailbox: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List mailboxes.",
        subcommands: [List.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List mailbox names in the account."
        )

        @OptionGroup var globals: Globals

        mutating func run() async throws {}
    }
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List emails in a mailbox (metadata only)."
    )

    @OptionGroup var globals: Globals

    @Argument(help: "Mailbox.")
    var mailbox: String

    mutating func run() async throws {}
}

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search emails in a mailbox (metadata only)."
    )

    @OptionGroup var globals: Globals

    @Argument(help: "Mailbox.")
    var mailbox: String

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

    @OptionGroup var globals: Globals

    @Argument(help: "Mailbox.")
    var mailbox: String

    @Argument(help: "IMAP location id in that mailbox.")
    var id: String

    @Argument(help: "Only these fields (from, to, subject, date, body).")
    var fields: [Field] = []

    mutating func run() async throws {}
}
