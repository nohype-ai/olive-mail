import Testing
import ArgumentParser
@testable import OliveMail

@Test func listRuns() async throws {
    let result = try await #require(
        processExitsWith: .success,
        observing: [\.standardOutputContent]
    ) {
        var command = try Email.List.parse([])
        try await command.run()
    }
    #expect(result.standardOutputContent.isEmpty)
}

@Test func rootSubcommandsExist() {
    var names: Set<String> = []
    for command in OliveMail.configuration.subcommands {
        names.insert(command._commandName)
    }
    #expect(names == ["account", "mailbox", "email"])

    var account: Set<String> = []
    for command in Account.configuration.subcommands {
        account.insert(command._commandName)
    }
    #expect(account == ["list", "add"])

    var mailbox: Set<String> = []
    for command in Mailbox.configuration.subcommands {
        mailbox.insert(command._commandName)
    }
    #expect(mailbox == ["list"])

    var email: Set<String> = []
    for command in Email.configuration.subcommands {
        email.insert(command._commandName)
    }
    #expect(email == ["list", "search", "show"])
}

@Test(arguments: [
    ["account", "list"],
    ["account", "list", "--json"],
    ["account", "add"],
    ["account", "add", "you@example.com", "--imap", "imaps://imap.example.com:993"],
    ["mailbox", "list"],
    ["mailbox", "list", "-a", "hi@nohype.ai"],
    ["email", "list"],
    ["email", "list", "-m", "MyInbox"],
    ["email", "list", "-m", "MyProjectMailbox"],
    ["email", "list", "-a", "hi@nohype.ai", "-m", "MyProjectMailbox"],
    ["email", "list", "--json", "-m", "MyInbox"],
    ["email", "search", "from", "alice@client.com"],
    ["email", "search", "-m", "MyInbox", "from", "alice@client.com"],
    ["email", "search", "-m", "MyProjectMailbox", "after", "2026-01-01"],
    ["email", "search", "-m", "MyProjectMailbox", "from", "alice@client.com", "after", "2026-01-01"],
    ["email", "show", "42"],
    ["email", "show", "-m", "MyInbox", "42"],
    ["email", "show", "-m", "MyProjectMailbox", "108"],
    ["email", "show", "-m", "MyInbox", "42", "from"],
    ["email", "show", "-m", "MyInbox", "42", "from", "to", "subject"],
    ["email", "show", "-m", "MyProjectMailbox", "108", "body"],
    ["email", "show", "-m", "MyProjectMailbox", "108", "from", "date", "body"],
] as [[String]])
func commandExists(_ args: [String]) throws {
    _ = try OliveMail.parseAsRoot(args)
}

@Test(arguments: [
    ["auth"],
    ["envelope", "list"],
    ["message", "send"],
    ["smtp"],
    ["list"],
    ["search"],
    ["show"],
    ["email", "show"],
    ["email", "show", "-m", "MyInbox"],
    ["email", "show", "-m", "MyInbox", "42", "bogus"],
] as [[String]])
func commandDoesNotExist(_ args: [String]) {
    #expect(throws: (any Error).self) {
        try OliveMail.parseAsRoot(args)
    }
}
