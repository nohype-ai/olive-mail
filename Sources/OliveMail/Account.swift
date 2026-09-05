import ArgumentParser

struct Account: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Accounts.",
        subcommands: [
            Add.self,
            // List.self, // MVP: no multi-account
        ]
    )

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add an account (IMAP credentials)."
        )

        @Argument(help: "Email address.")
        var email: String?

        @Option(help: "IMAP server URL (e.g. imaps://imap.example.com:993).")
        var imap: String?

        mutating func run() async throws {}
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List accounts."
        )

        @Flag(help: "JSON output.")
        var json = false

        mutating func run() async throws {}
    }
}