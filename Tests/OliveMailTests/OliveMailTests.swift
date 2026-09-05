import Testing
import ArgumentParser
@testable import OliveMail

@Test func helloWorld() async throws {
    let result = try await #require(
        processExitsWith: .success,
        observing: [\.standardOutputContent]
    ) {
        var command = try OliveMail.parse([])
        try await command.run()
    }
    #expect(result.standardOutputContent.contains("Hello, world!".utf8))
}
