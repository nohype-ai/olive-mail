import Testing
import ArgumentParser
@testable import OliveMail

@Test func listRuns() async throws {
    let result = try await #require(
        processExitsWith: .success,
        observing: [\.standardOutputContent]
    ) {
        var command = try List.parse(["MyInbox"])
        try await command.run()
    }
    #expect(result.standardOutputContent.isEmpty)
}

@Test func rootSubcommandsExist() {
    var names: Set<String> = []
    for command in OliveMail.configuration.subcommands {
        names.insert(command._commandName)
    }
    #expect(names == ["auth", "mailbox", "list", "search", "show"])

    var mailbox: Set<String> = []
    for command in Mailbox.configuration.subcommands {
        mailbox.insert(command._commandName)
    }
    #expect(mailbox == ["list"])
}

@Test(arguments: [
    ["auth"],
    ["auth", "you@example.com", "--imap", "imaps://imap.example.com:993"],
    ["mailbox", "list"],
    ["mailbox", "list", "-a", "hi@nohype.ai"],
    ["list", "MyInbox"],
    ["list", "MyProjectMailbox"],
    ["list", "-a", "hi@nohype.ai", "MyProjectMailbox"],
    ["list", "--json", "MyInbox"],
    ["search", "MyInbox", "from", "alice@client.com"],
    ["search", "MyProjectMailbox", "after", "2026-01-01"],
    ["search", "MyProjectMailbox", "from", "alice@client.com", "after", "2026-01-01"],
    ["show", "MyInbox", "42"],
    ["show", "MyProjectMailbox", "108"],
    ["show", "MyInbox", "42", "from"],
    ["show", "MyInbox", "42", "from", "to", "subject"],
    ["show", "MyProjectMailbox", "108", "body"],
    ["show", "MyProjectMailbox", "108", "from", "date", "body"],
] as [[String]])
func commandExists(_ args: [String]) throws {
    _ = try OliveMail.parseAsRoot(args)
}

@Test(arguments: [
    ["envelope", "list"],
    ["message", "send"],
    ["smtp"],
    ["list"],
    ["search"],
    ["show"],
    ["show", "42"],
    ["show", "MyInbox", "42", "bogus"],
] as [[String]])
func commandDoesNotExist(_ args: [String]) {
    #expect(throws: (any Error).self) {
        try OliveMail.parseAsRoot(args)
    }
}
