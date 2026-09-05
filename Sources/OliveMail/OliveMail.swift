import ArgumentParser

@main
struct OliveMail: AsyncParsableCommand {
    mutating func run() async throws {
        print("Hello, world!")
    }
}
