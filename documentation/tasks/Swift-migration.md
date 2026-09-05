# Task: compiled olive-mail (Swift)

Replace the bash Himalaya wrapper with a Swift CLI that owns the agent-facing API. Himalaya is the v1 backend, not the interface. This is the precondition [Daemon-user.md](Daemon-user.md) names; that file is not this rewrite.

Status: todo  
Date: 2026-09-05  
Depends on: live IMAP already working via bash `olive-mail auth`

Package already exists: `Package.swift` (ArgumentParser 1.8.2, swift-system 1.8.1, Swift 6.4), `Sources/OliveMail/OliveMail.swift` (`AsyncParsableCommand` hello-world), tests. This task fills that in and retires `./olive-mail` bash.

Platforms: Linux and macOS (same commands, same `~/.config/olive-mail` paths).

## Why this, and not a Himalaya passthrough

The bash tool `exec`s `himalaya -c config "$@"`. That makes olive-mail’s API Himalaya’s API. We cannot:

- regulate individual commands in the permission matrix (later TODO; [Daemon-user.md](Daemon-user.md) matrix columns)
- swap backend (Maildir cache, MailKit, native IMAP) without breaking agents
- keep `--help` as ours

So: **our commands, our help, our ids-as-we-define-them.** Himalaya stays an implementation of a `MailBackend`. Agents never type `himalaya` and never see Himalaya flags.

## Goal

- `olive-mail` is the Swift binary on `PATH` (`~/.local/bin`, same install story as bash).
- First-class ArgumentParser commands. `--help` is ours.
- Read-only MVP: `auth`, `mailbox list`, `list`, `search`, `show`.
- HimalayaBackend: exec Himalaya with **our** config, parse JSON, map to our types.
- Send / SMTP / IMAP-raw / `message send` / `--send` are **absent** (not a reject-after-parse of Himalaya argv).
- Same secret files as today: `~/.config/olive-mail/config.toml` + `<email>.pass` (`0600`).

## Current

```
agent  →  olive-mail (bash)  →  himalaya -c ~/.config/olive-mail/config.toml …
                                  passwd.command = cat ~/.config/olive-mail/<email>.pass
```

Agent argv is Himalaya (`envelope list`, `message read 42`, …). `deny_send` is a wrapper check.

## Target

```
agent  →  olive-mail (Swift, ArgumentParser)
              │  auth | mailbox list | list | search | show
              ▼
         MailBackend
              └─ HimalayaBackend (v1)  →  himalaya -c config --json …
              └─ later: Maildir / MailKit / …
```

Permission checks (not this task) sit between the command and `MailBackend`, keyed by **our** command names and typed args (`list`, `show`, `show`+`body`, mailbox, …).

## Agent-facing API (MVP)

Hierarchy: account → mailbox → email → fields. Unix shape: account is `-a`, mailbox is a folder, `list` is `ls`, `show` is `cat`.

Account: `-a you@example.com` on the root. Omitted = the `default = true` account in `config.toml`.

IMAP id is a **location**, not an identity. Always mailbox + id. `42` in `MyInbox` and `42` in `MyProjectMailbox` are different emails. A move invalidates the old pair. No `show 42`. (Stable ids — Message-ID or our integer — are a later task.)

```
olive-mail mailbox list
olive-mail -a hi@nohype.ai mailbox list

olive-mail list MyInbox
olive-mail list MyProjectMailbox
olive-mail -a hi@nohype.ai list MyProjectMailbox

olive-mail search MyInbox from alice@client.com
olive-mail search MyProjectMailbox after 2026-01-01
olive-mail search MyProjectMailbox from alice@client.com after 2026-01-01

olive-mail show MyInbox 42
olive-mail show MyProjectMailbox 108
olive-mail show MyInbox 42 from
olive-mail show MyInbox 42 from to subject
olive-mail show MyProjectMailbox 108 body
olive-mail show MyProjectMailbox 108 from date body
```

Semantics:

| Command | Returns | Body |
|---|---|---|
| `mailbox list` | mailbox names | — |
| `list` / `search` | many emails, metadata only (`id`, `from`, `to`, `date`, `subject`) | never |
| `show <mailbox> <id>` | exactly one email; default = headers | only if `body` is asked |

`list` and `search` require a mailbox (no implicit “current folder”). `search` is `list` plus query; do **not** expose Himalaya’s search DSL. MVP query: `from <addr>` and `after <YYYY-MM-DD>` as above (extend later).

`--help` / `-h`: ArgumentParser. Root lists our commands. There is no Himalaya help, no passthrough, no `@Argument(parsing: .captureForPassthrough)` for unknown verbs.

`--json` on the root (we own the schema). Human output is the default. Agents should pass `--json`.

`auth` stays ours (not a backend op):

```
olive-mail auth you@example.com --imap imaps://imap.example.com:993
```

TTY: prompt email / IMAP / password. Non-TTY: email + `--imap`, password on stdin. Writes `config.toml` + `<email>.pass` `0600`. MVP may still overwrite `config.toml` (multiple-accounts TODO is separate).

## Backend

```swift
protocol MailBackend: Sendable {
    func listMailboxes(account: Account) async throws -> [Mailbox]
    func listEmails(account: Account, mailbox: Mailbox) async throws -> [EmailSummary]
    func searchEmails(account: Account, mailbox: Mailbox, query: SearchQuery) async throws -> [EmailSummary]
    func showEmail(account: Account, mailbox: Mailbox, id: EmailLocationID, fields: [EmailField]) async throws -> EmailView
}
```

`HimalayaBackend` translates those into `himalaya -c <config> --json …` (inject `-c`; never expose `-c` on our CLI). Parse JSON into our types. Himalaya argv, JSON keys, and `--backend` stay inside this type.

Do not declare Himalaya flags on ArgumentParser commands. Do not forward leftover argv.

## Non-goals

- Granular permissions / matrix (separate TODO; this task only makes commands addressable)
- Daemon-user privilege split ([Daemon-user.md](Daemon-user.md) starts after this)
- Local Maildir cache ([Caching.md](Caching.md) — its “unchanged Himalaya argv” is superseded by this API; cache talks to `MailBackend`, agents still call `list` / `show`)
- Stable ids (Message-ID or per-account integers)
- Send, draft, copy, move, flags, attachments download
- Protocol CLIs (`imap`, `gmail`, `smtp`, …)
- Homebrew formula, agent skill, OAuth
- Replacing Himalaya in v1 (it is the backend, not the product)

## Layout (repo)

Keep the executable target. Split files under `Sources/OliveMail/` as needed (root command, subcommands, backend, paths/install). No extra library target unless tests force it.

Machine paths unchanged:

```
~/.config/olive-mail/config.toml
~/.config/olive-mail/<email>.pass
```

Himalaya remains a **runtime** dependency of `HimalayaBackend` (brew install on first use, same as bash).

## Tasks

### 1. CLI skeleton (no IMAP)

- [ ] Root `OliveMail`: `commandName` `olive-mail`, `-a/--account`, `--json`, subcommands below. Empty `olive-mail` / `--help` is our help, not Himalaya’s, not “Hello, world!”.
- [ ] `auth`, `mailbox list`, `list`, `search`, `show` as `AsyncParsableCommand`s. Parse tests for the examples in this file (including rejection of unknown verbs and of `show 42` without a mailbox).
- [ ] `show`: positional mailbox, positional id, remaining field names (`from`, `to`, `subject`, `date`, `body`). Unknown field = error.
- [ ] Replace the hello-world test.

### 2. Paths, auth, Himalaya install

- [ ] Port `set_paths` / `olive_mail_auth` from bash: `XDG_CONFIG_HOME` / `~/.config/olive-mail`, pass file `0600`, `config.toml` shape matching `config.toml.example` (no SMTP).
- [ ] Port `ensure_himalaya` (Homebrew + `brew install himalaya` if missing). Fail clearly if still not on `PATH`.
- [ ] Port `ensure_on_path`: copy/symlink **this binary** (resolved `argv[0]`), not the repo, to `~/.local/bin/olive-mail` and `/usr/local/bin` if writable. Same shell-rc snippet as bash (`olive-mail: user bin`).
- [ ] Trigger install-on-path + ensure-himalaya from `auth` and from mail commands that need the backend (not from `--help`).
- [ ] Mail commands without config/pass: same errors as bash (`Run: olive-mail auth`).

### 3. `MailBackend` + HimalayaBackend

- [ ] Protocol + types (`Mailbox`, `EmailSummary`, `EmailLocationID`, `EmailField`, `SearchQuery`, `EmailView`).
- [ ] `HimalayaBackend`: one process invoke helper (use swift-system; preserve stdout/stderr/exit). Always `-c` our config. `--json` for parseable output.
- [ ] Map `mailbox list` → Himalaya mailbox list. Surface **IMAP mailbox ids** (e.g. `INBOX`, `MyProjectMailbox`), not Himalaya aliases only. Keep using `mailbox.alias.inbox` in config when the host’s inbox is not `INBOX`.
- [ ] Map `list` / `show` / `search` onto Himalaya envelope/message calls **with** `-m/--mailbox` and Himalaya’s per-mailbox id. Our location id **is** that Himalaya/IMAP id for MVP.
- [ ] `show` without `body`: headers only (do not fetch/print the body). `body` in the field list is the only path that reads content.
- [ ] Search: translate `from` / `after` into whatever Himalaya search we call. If Himalaya’s DSL is the only option, keep that string **inside** the backend; the CLI stays `from` / `after`.

### 4. Retire bash

- [ ] Root `./olive-mail` is no longer the product. Either delete it or make it a one-line exec of a release binary (do not keep a second implementation).
- [ ] `swift build -c release` is how the installable binary is produced. Document the one command that ends with `olive-mail` on `PATH` (e.g. `swift run olive-mail auth …` from a checkout still allowed if it installs the built binary).
- [ ] No code path `exec himalaya "$@"` with agent argv.

### 5. Docs

- [ ] README **Now**: Swift CLI, own read API, Himalaya backend. Drop “type `olive-mail` wherever Himalaya docs say `himalaya`”. Usage block = the examples in this file.
- [ ] README **Next** still granular permissions; mention daemon-user needs this binary.
- [ ] `config.toml.example` only if the generated shape changes (should not).
- [ ] [TODO.md](../TODO.md): this item checked off when done.
- [ ] [Caching.md](Caching.md): note that agent argv is `list` / `show` / …, not `envelope` / `message`. Do not implement cache here.

## Order

1. Skeleton + parse tests (help is ours)
2. Paths + `auth` + Himalaya/PATH bootstrap
3. `mailbox list` live
4. `list` + `show` (headers) live
5. `show … body` + `search`
6. Delete bash product path
7. README

## Done when

- `olive-mail --help` lists `auth`, `mailbox`, `list`, `search`, `show` and does not mention Himalaya subcommands.
- `olive-mail auth` writes the same config/pass layout as today.
- `mailbox list`, `list MyInbox`, `show MyInbox 42`, `show MyInbox 42 body`, and a `search` work against a real account via Himalaya.
- `olive-mail envelope list` / `olive-mail message send` fail as **unknown commands**.
- Binary on `PATH` is Swift; bash wrapper is gone.
- Tests cover parsing and at least a fake `MailBackend` for `list`/`show` (no live IMAP required in CI).
- Nothing in the repo names a real mailbox.

## Risks

| Risk | Mitigation |
|---|---|
| Existing bots use Himalaya argv (`envelope list`, …) | Intentional break. README + company bot docs; no compatibility shim |
| Himalaya JSON / id column is sequence vs UID | Treat whatever Himalaya `list` prints as the location id `show` must accept; document it |
| `Inbox` vs `INBOX` | Same as today: `mailbox list` + `mailbox.alias.inbox` |
| `auth` overwrites `config.toml` | Leave as today; multiple-accounts TODO |
| Help vs `show … --help` | `--help` is ours everywhere; field name `help` is not a field |
| Himalaya missing / old brew build | `ensure_himalaya`; fail with install text, do not silent-passthrough |
| Body accidentally included in `list` / default `show` | Tests on the mapper: summaries have no body; default fields exclude `body` |
| [Caching.md](Caching.md) still says unchanged argv | Update that file’s command names when this lands, before cache work |

## Out of scope until this works

Daemon-user, cache/sync, stable ids, send/drafts, permission matrix, Homebrew formula.
