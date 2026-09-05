import ArgumentParser

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
