import ArgumentParser

@main
struct OliveMail: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Real email context for agents.",
        subcommands: [Account.self, Mailbox.self, Email.self]
    )
}
