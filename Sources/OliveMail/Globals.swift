import ArgumentParser

struct Globals: ParsableArguments {
    // MVP: no multi-account
    // @Option(name: .shortAndLong, help: "Account. Omitted: all accounts.")
    // var account: String?

    @Flag(help: "JSON output.")
    var json = false
}
