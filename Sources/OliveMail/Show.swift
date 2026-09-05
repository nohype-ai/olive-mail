import ArgumentParser

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
