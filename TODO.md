# To do

## Open

- [ ] encrypt password and isolate it from agents where the user has root access or can manage unix users (like on a personal macOS machine)
	- [ ] Keychain for the app password on macOS
	- [ ] systemd-creds on Linux
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
- [ ] At what point should we make it a compiled binary with an actual language (like Rust or Swift)?
- [ ] OAuth for Gmail/Outlook accounts? What would it take?

## Done

- [x] Decouple the repo from any real mailbox
- [x] Grok-bot PATH (user-bin symlink, not the repo directory)
- [x] Apache 2.0
- [x] Public README
- [x] macOS support (same ~/.config/olive-mail paths as Linux; Keychain is separate)
