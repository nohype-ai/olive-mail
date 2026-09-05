import ArgumentParser

extension Mailbox {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List mailbox names in the account."
        )

        @OptionGroup var globals: Globals

        mutating func run() async throws {}
    }
}
