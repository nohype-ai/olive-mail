protocol MailBackend: Sendable {
    // MVP: no multi-account; account stays commented
    // func listMailboxes(account: String?) async throws -> [Mailbox.Info]
    func listMailboxes() async throws -> [Mailbox.Info]
    func listEmails(mailbox: String?, limit: Int) async throws -> [Email.Summary]
    func showEmail(mailbox: String, id: String) async throws -> Email.View
}
