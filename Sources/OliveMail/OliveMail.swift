import ArgumentParser

@main
struct OliveMail: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Real email context for agents.",
        subcommands: [Auth.self, Mailbox.self, List.self, Search.self, Show.self]
    )
}
