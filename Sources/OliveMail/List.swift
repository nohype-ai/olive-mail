import ArgumentParser

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List emails in a mailbox (metadata only)."
    )

    @OptionGroup var globals: Globals

    @Argument(help: "Mailbox.")
    var mailbox: String

    mutating func run() async throws {}
}
