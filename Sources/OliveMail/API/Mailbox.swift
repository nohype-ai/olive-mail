import ArgumentParser
import Foundation

struct Mailbox: AsyncParsableCommand {
    struct Info: Codable, Equatable, Sendable {
        var id: String
        var name: String
    }

    static let configuration = CommandConfiguration(
        abstract: "Mailboxes.",
        subcommands: [List.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List mailboxes."
        )

        @OptionGroup var globals: Globals

        mutating func run() async throws {
            let paths = try Paths.resolve()
            try paths.requireConfigured()
            let backend = HimalayaBackend(paths: paths)
            let mailboxes = try await backend.listMailboxes()
            if globals.json {
                try printJSON(["mailboxes": mailboxes])
            } else {
                for mailbox in mailboxes {
                    print(mailbox.id)
                }
            }
        }
    }
}
