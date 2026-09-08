import Testing
import ArgumentParser
#if canImport(System)
import System
#else
import SystemPackage
#endif
@testable import OliveMail

// Locate HOME / XDG on this machine is fine. Do not create or overwrite
// files outside a temp directory.

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
    #expect(account == ["add"])

    var mailbox: Set<String> = []
    for command in Mailbox.configuration.subcommands {
        mailbox.insert(command._commandName)
    }
    #expect(mailbox == ["list"])

    var email: Set<String> = []
    for command in Email.configuration.subcommands {
        email.insert(command._commandName)
    }
    #expect(email == ["list", "show"])
}

@Test(arguments: [
    // MVP: no multi-account
    // ["account", "list"],
    // ["account", "list", "--json"],
    ["account", "add"],
    ["account", "add", "you@example.com", "--imap", "imaps://imap.example.com:993"],
    ["account", "add", "you@example.com", "--imap", "imap.example.com:993"],
    ["account", "add", "you@example.com", "--imap", "imap.example.com"],
    ["mailbox", "list"],
    // ["mailbox", "list", "-a", "hi@nohype.ai"],
    ["email", "list"],
    ["email", "list", "-m", "MyInbox"],
    ["email", "list", "-m", "MyProjectMailbox"],
    // ["email", "list", "-a", "hi@nohype.ai", "-m", "MyProjectMailbox"],
    ["email", "list", "--json", "-m", "MyInbox"],
    // MVP: filters not implemented
    // ["email", "list", "--from", "alice@client.com"],
    // ["email", "list", "-m", "MyInbox", "--from", "alice@client.com"],
    // ["email", "list", "-m", "MyProjectMailbox", "--after", "2026-01-01"],
    // ["email", "list", "--from", "alice@client.com", "--to", "bob@client.com", "--after", "2026-01-01", "--contains", "invoice"],
    ["email", "list", "--limit", "5"],
    ["email", "show", "-m", "MyInbox", "42"],
    ["email", "show", "-m", "MyProjectMailbox", "108"],
    ["email", "show", "-m", "MyInbox", "42", "--fields", "from"],
    ["email", "show", "-m", "MyInbox", "42", "--fields", "from,to,subject"],
    ["email", "show", "-m", "MyProjectMailbox", "108", "--fields", "body"],
    ["email", "show", "-m", "MyProjectMailbox", "108", "--fields", "from,date,body"],
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
    ["email", "search"],
    ["show"],
    ["email", "show"],
    ["email", "show", "42"],
    ["email", "show", "-m", "MyInbox"],
    ["email", "show", "-m", "MyInbox", "42", "from"],
    ["email", "show", "-m", "MyInbox", "42", "--fields", "bogus"],
    ["email", "show", "-m", "MyInbox", "42", "--fields", "from,bogus"],
    ["account", "list"],
] as [[String]])
func commandDoesNotExist(_ args: [String]) {
    #expect(throws: (any Error).self) {
        try OliveMail.parseAsRoot(args)
    }
}

@Test func pathsFromHome() throws {
    let paths = try FilePaths.resolve(environment: ["HOME": "/Users/you"])
    #expect(paths.directory == FilePath("/Users/you/.config/olive-mail"))
    #expect(paths.himalayaConfig == FilePath("/Users/you/.config/olive-mail/config.toml"))
    #expect(paths.passFile(email: "you@example.com") == FilePath("/Users/you/.config/olive-mail/you@example.com.pass"))
}

@Test func pathsFromXDGConfigHome() throws {
    let paths = try FilePaths.resolve(environment: [
        "HOME": "/Users/you",
        "XDG_CONFIG_HOME": "/tmp/xdg-config",
    ])
    #expect(paths.directory == FilePath("/tmp/xdg-config/olive-mail"))
    #expect(paths.himalayaConfig == FilePath("/tmp/xdg-config/olive-mail/config.toml"))
}

@Test func pathsNeedHome() {
    #expect(throws: OliveMailError.missingHome) {
        try FilePaths.resolve(environment: [:])
    }
}

@Test func pathsResolveOnThisMachine() throws {
    let paths = try FilePaths.resolve()
    #expect(paths.directory.lastComponent?.string == "olive-mail")
    #expect(paths.himalayaConfig == paths.directory.appending("config.toml"))
}
