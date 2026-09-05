import ArgumentParser

struct Mailbox: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mailboxes.",
        subcommands: [List.self]
    )
    
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List mailboxes."
        )

        @OptionGroup var globals: Globals

        mutating func run() async throws {}
    }
}