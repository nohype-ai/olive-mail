import ArgumentParser

struct Mailbox: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List mailboxes.",
        subcommands: [List.self]
    )
}
