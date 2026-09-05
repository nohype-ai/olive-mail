import ArgumentParser

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
