import ArgumentParser

struct Globals: ParsableArguments {
    @Option(name: .shortAndLong, help: "Email account.")
    var account: String?

    @Flag(help: "JSON output.")
    var json = false
}
