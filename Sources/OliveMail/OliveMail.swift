import ArgumentParser

@main
struct OliveMail: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "olive-mail",
        abstract: "Real email context for agents.",
        subcommands: [Account.self, Mailbox.self, Email.self]
    )
}
