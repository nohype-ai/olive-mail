# To do

## Open

- [ ] Compiled olive-mail (Swift): own read API, Himalaya as backend ([tasks/Swift-migration.md](tasks/Swift-migration.md))
- [ ] Daemon-user install: extra Unix user + daemon, fallback to today’s pass file ([tasks/Daemon-user.md](tasks/Daemon-user.md))
- [ ] multiple accounts/addresses
	- [ ] `auth` should add or update an account, not overwrite `config.toml`
- [ ] Distribute as homebrew formula
- [ ] Include agent skill
- [ ] Granular permissions on this CLI: folders, senders, dates; read vs draft vs send; metadata first, body only when asked
- [ ] Local incremental cache behind `olive-mail` ([tasks/Caching.md](tasks/Caching.md))
- [ ] Self-hosted secret? What would it take?
- [ ] Grok Bot Connector? What would it take?
- [ ] RAG, search, summarization?
- [ ] Redaction / anonymization layer?
- [ ] OAuth for Gmail/Outlook accounts? What would it take?

## Done

- [x] Decouple the repo from any real mailbox
- [x] Grok-bot PATH (user-bin symlink, not the repo directory)
- [x] Apache 2.0
- [x] Public README
- [x] macOS support (same ~/.config/olive-mail paths as Linux; Keychain is separate)
