# Task: compiled olive-mail (Swift)

Replace the bash Himalaya wrapper with a Swift CLI that owns the agent-facing API. Himalaya is the v1 backend, not the interface. This is the precondition [Daemon-user.md](Daemon-user.md) names; that file is not this rewrite.

Status: done  
Date: 2026-09-05  
Depends on: live IMAP already working via bash `olive-mail auth`

Package already exists: `Package.swift` (ArgumentParser 1.8.2, swift-system 1.8.1, Swift 6.4), `Sources/OliveMail/` (ArgumentParser skeleton), tests. This task fills that in and retires `./olive-mail` bash.

Platforms: Linux and macOS (same commands, same `~/.config/olive-mail` paths).

## Why this, and not a Himalaya passthrough

The bash tool `exec`s `himalaya -c config "$@"`. That makes olive-mail’s API Himalaya’s API. We cannot:

- regulate individual commands in the permission matrix (later TODO; [Daemon-user.md](Daemon-user.md) matrix columns)
- swap backend (Maildir cache, MailKit, native IMAP) without breaking agents
- keep `--help` as ours

So: **our commands, our help, our ids-as-we-define-them.** Himalaya stays an implementation of a `MailBackend`. Agents never type `himalaya` and never see Himalaya flags.

## Goal

- `olive-mail` is the Swift binary. Compile it, run it. Himalaya must be on `PATH`; if missing, fail with install text (`brew install himalaya`). Do not auto-install Homebrew/Himalaya. Do not treat toolchain or formula packaging as this task.
- First-class ArgumentParser commands. `--help` is ours.
- Read-only MVP: `account add`, `mailbox list`, `email list`, `email show`.
- HimalayaBackend: exec Himalaya with **our** config, parse JSON, map to our types.
- Send / SMTP / IMAP-raw / `message send` / `--send` are **absent** (not a reject-after-parse of Himalaya argv).
- Same secret files as today: `~/.config/olive-mail/config.toml` + `<email>.pass` (`0600`).

What the intended API already has in the skeleton but this MVP does **not** ship: `account list`, `-a/--account`, `email list` filters (`--from`, `--to`, `--after`, `--contains`). **Comment those out in code; do not delete them.** Parse tests for them stay in the file, commented.

## Current

```
agent  →  olive-mail (bash)  →  himalaya -c ~/.config/olive-mail/config.toml …
                                  passwd.command = cat ~/.config/olive-mail/<email>.pass
```

Agent argv is Himalaya (`envelope list`, `message read 42`, …). `deny_send` is a wrapper check.

## Target

```
agent  →  olive-mail (Swift, ArgumentParser)
              │  account add | mailbox list | email list | email show
              ▼
         MailBackend
              └─ HimalayaBackend (v1)  →  himalaya -c config --json …
              └─ later: Maildir / MailKit / …
```

Permission checks (not this task) sit between the command and `MailBackend`, keyed by **our** command names and typed args. Partial read rights **redact** denied fields on `email show`; they do not change the command.

## Agent-facing API (MVP)

Hierarchy: account → mailbox → email. Noun-verb: `account`, `mailbox`, and `email` are dispatchers.

One account. `account add` is today’s `auth`: overwrite `config.toml` + pass file. No `account list`. No `-a/--account`.

Mailbox is an **option**. Omitted on `email list` / `mailbox list` means **all mailboxes** (not the config inbox alias). `email show` **requires** `-m/--mailbox`. Unscoped `email show 42` fails (mailbox option missing). Himalaya v2 ids are per-mailbox IMAP UIDs: `42` in Inbox and `42` in Sent are different emails. Do not probe uniqueness. (Stable ids — Message-ID or our integer — are a later task.)

`email list` is newest first, capped at `--limit` (default 20). List rows include mailbox (and account, when we have several) so a following `email show -m …` can be precise. No list filters in this MVP.

Unscoped `email list` is the API even before a local cache exists (v1 may hit live IMAP and be slow; that is fine). [Caching.md](Caching.md) is a later **performance** optimization of the same commands, not a different interface.

```
olive-mail account add you@example.com --imap imaps://imap.example.com:993

olive-mail mailbox list

olive-mail email list
olive-mail email list -m MyInbox
olive-mail email list -m MyProjectMailbox
olive-mail email list --limit 5

olive-mail email show -m MyInbox 42
olive-mail email show -m MyProjectMailbox 108
olive-mail email show -m MyInbox 42 from
```

Semantics:

| Command | Returns |
|---|---|
| `account add` | writes credentials (not a Himalaya op); overwrites existing auth |
| `mailbox list` | mailbox names for the configured account |
| `email list` | newest emails first, default `--limit 20`; columns include mailbox, `id`, `from`, `to`, `date`, `subject` |
| `email show -m <mailbox> <id>` | that one email (metadata + body; HTML is fine) |
| `email show -m <mailbox> <id> from` | only that field (optional; same for `to`, `subject`, `date`, `body`) |

`email show` means show the email. Partial read rights (later) redact denied parts of that same command; they do not invent a headers-only verb.

No `email search` command. No list filters in this MVP (`--from`, `--to`, `--after`, `--contains` stay in the tree, commented). Himalaya’s search DSL stays inside the backend when those return.

`--help` / `-h`: ArgumentParser. Root lists `account`, `mailbox`, `email`. There is no Himalaya help, no passthrough, no `@Argument(parsing: .captureForPassthrough)` for unknown verbs. No `auth` command (`account add` replaced it).

`--json` on the leaf (we own the schema). Human output is the default. Agents should pass `--json`.

`account add` is ours (not a backend op):

```
olive-mail account add you@example.com --imap imaps://imap.example.com:993
```

TTY: prompt email / IMAP / password. Non-TTY: email + `--imap`, password on stdin. Writes `config.toml` + `<email>.pass` `0600`. Overwrites `config.toml` (multiple-accounts TODO is `account add` should add or update, not clobber).

Commented-out (not this MVP; keep in code):

```
olive-mail account list
olive-mail mailbox list -a hi@nohype.ai
olive-mail email list -a hi@nohype.ai -m MyProjectMailbox
olive-mail email list --from alice@client.com
olive-mail email list -m MyInbox --from alice@client.com
olive-mail email list --from alice@client.com --to bob@client.com --after 2026-01-01 --contains invoice
olive-mail email show 42
```

## Backend

```swift
protocol MailBackend: Sendable {
    func listMailboxes(account: Account?) async throws -> [Mailbox]
    func listEmails(account: Account?, mailbox: Mailbox?, filter: EmailFilter) async throws -> [EmailSummary]
    func showEmail(account: Account?, mailbox: Mailbox?, id: EmailLocationID, fields: [EmailField]) async throws -> EmailView
}
```

MVP calls pass `account: nil` and an empty/default `EmailFilter`. The extra parameters stay on the protocol.

`HimalayaBackend` translates those into `himalaya -c <config> --json …` (inject `-c`; never expose `-c` on our CLI). Parse JSON into our types. Himalaya argv, JSON keys, and `--backend` stay inside this type.

Unscoped `email list` (no `-m`): `mailbox list`, then for each mailbox `himalaya envelope list -m <mailbox> --page-size <limit> --page 1`. Merge, sort newest first, cut to `--limit`. Naive N invocations is the implementation. Do not silently restrict scope to inbox.

`email show`: `himalaya message read -m <mailbox> <id> --json`. Print metadata + body. HTML is fine. Optional field names just narrow that. Do not block on Himalaya’s json-schema for `message read`.

Do not declare Himalaya flags on ArgumentParser commands. Do not forward leftover argv.

## Non-goals

- Multi-account (`account list`, `-a`, add-or-update instead of overwrite)
- `email list` filters (`--from`, `--to`, `--after`, `--contains`)
- Unscoped `email show` / uniqueness probing / stable ids
- Auto-install of Homebrew or Himalaya; Homebrew formula
- Granular permissions / matrix (separate TODO; this task only makes commands addressable)
- Daemon-user privilege split ([Daemon-user.md](Daemon-user.md) starts after this)
- Local Maildir cache ([Caching.md](Caching.md) — later; same agent commands, faster). Its “unchanged Himalaya argv” is superseded.
- Send, draft, copy, move, flags, attachments download
- Protocol CLIs (`imap`, `gmail`, `smtp`, …)
- Agent skill, OAuth
- Replacing Himalaya in v1 (it is the backend, not the product)

## Layout (repo)

Keep the executable target. Split files under `Sources/OliveMail/` as needed (root command, subcommands, backend, paths). No extra library target unless tests force it.

Machine paths unchanged:

```
~/.config/olive-mail/config.toml
~/.config/olive-mail/<email>.pass
```

Himalaya is a **runtime** dependency of `HimalayaBackend`. If `himalaya` is not on `PATH`, fail with install text. Do not silent-passthrough.

## Tasks

### 1. CLI skeleton (no IMAP)

- [x] Root `OliveMail` is a dispatcher: `account`, `mailbox`, `email`. Empty `olive-mail` / `--help` is our help, not Himalaya’s.
- [x] Leaves wired for MVP: `account add`, `mailbox list`, `email list`, `email show`. `--json` on mail leaves; `-m/--mailbox` on `email` leaves (`email list`: omitted = all; `email show`: required). `--limit` on `email list` (default 20). Comment out, do not delete: `account list`, `-a/--account`, list filters. Parse tests for the MVP examples (including rejection of `auth`, `email search`, `email show` without `-m` or without an id).
- [x] `email show`: required `-m/--mailbox`, positional id, optional field names (`from`, `to`, `subject`, `date`, `body`). Unknown field = error.
- [x] Replace the hello-world test.

### 2. Paths + `account add`

- [x] Port `set_paths` / bash `auth` into `account add`: `XDG_CONFIG_HOME` / `~/.config/olive-mail`, pass file `0600`, `config.toml` shape matching `config.toml.example` (no SMTP). Overwrite as today.
- [x] Mail commands: if `himalaya` is missing, fail with install text. If no config/pass: `Run: olive-mail account add`.
- [x] PATH bootstrap (`ensure_on_path`) and Homebrew auto-install (`ensure_himalaya`): omit from MVP; comment if ported, do not delete the idea.

### 3. `MailBackend` + HimalayaBackend

- [x] Protocol + types (`Mailbox`, `EmailSummary`, `EmailLocationID`, `EmailField`, `EmailFilter`, `EmailView`).
- [x] `HimalayaBackend`: one process invoke helper (use swift-system; preserve stdout/stderr/exit). Always `-c` our config. `--json` for parseable output.
- [x] Map `mailbox list` → Himalaya mailbox list. Surface **IMAP mailbox ids** (e.g. `INBOX`, `MyProjectMailbox`), not Himalaya aliases only. Keep using `mailbox.alias.inbox` in config when the host’s inbox is not `INBOX`.
- [x] Map `email list` / `email show` onto Himalaya envelope/message calls **with** `-m/--mailbox` and Himalaya’s per-mailbox id. Our location id **is** that Himalaya/IMAP UID for MVP.
- [x] `email show`: fetch and print that email (metadata + body). Optional field names just narrow the output. Permissions (later) redact; they do not change the command.
- [x] `email list`: per mailbox `envelope list -m … --page-size <limit> --page 1`; merge; sort newest first; cut to `--limit` (default 20). Filter translation stays commented with the CLI filters.

### 4. Retire bash

- [x] Root `./olive-mail` is no longer the product. Either delete it or make it a one-line exec of a release binary (do not keep a second implementation).
- [x] `swift build -c release` produces the binary. Document that.
- [x] No code path `exec himalaya "$@"` with agent argv.

### 5. Docs

- [x] README **Now**: Swift CLI, own read API, Himalaya backend. Drop “type `olive-mail` wherever Himalaya docs say `himalaya`”. Usage block = the MVP examples in this file. `auth` → `account add`.
- [x] README **Next** still granular permissions; mention daemon-user needs this binary.
- [x] `config.toml.example` only if the generated shape changes (should not).
- [x] [TODO.md](../TODO.md): this item checked off when done.
- [x] [Caching.md](Caching.md): note that agent argv is `mailbox list` / `email list` / `email show` / …, not `envelope` / `message`. Do not implement cache here.

## Order

1. Skeleton + parse tests (help is ours; omitted flags commented)
2. Paths + `account add`
3. `mailbox list` live
4. `email list` + `email show` live
5. Delete bash product path
6. README

## Done when

- `olive-mail --help` lists `account`, `mailbox`, `email` and does not mention Himalaya subcommands or `auth`.
- `olive-mail account add` writes the same config/pass layout as today (overwrite).
- `mailbox list`, `email list`, `email list -m MyInbox`, `email show -m MyInbox 42` work against a real account via Himalaya. Unscoped `email list` returns at most 20, newest first.
- `olive-mail email show 42` fails (mailbox option missing).
- `olive-mail envelope list` / `olive-mail message send` / `olive-mail account list` fail as **unknown commands**.
- Missing `himalaya` fails with install text.
- Binary is Swift; bash wrapper is gone.
- Tests cover parsing and at least a fake `MailBackend` for `email list` / `email show` (no live IMAP required in CI).
- Nothing in the repo names a real mailbox.
- Omitted API is still in the tree, commented, not deleted.

## Risks

| Risk | Mitigation |
|---|---|
| Existing bots use Himalaya argv (`envelope list`, …) | Intentional break. README + company bot docs; no compatibility shim |
| Himalaya JSON / id column is sequence vs UID | v2 prints IMAP UID as `id`; `email show` requires `-m` and that id |
| `Inbox` vs `INBOX` | Same as today: `mailbox list` + `mailbox.alias.inbox` |
| `account add` overwrites `config.toml` | Leave as today; multiple-accounts TODO |
| Help vs `email show … --help` | `--help` is ours everywhere; field name `help` is not a field |
| Himalaya missing | Fail with install text, do not silent-passthrough |
| Body leaking via `email list` | Summaries never include `body`; only `email show` does (then redaction, later) |
| [Caching.md](Caching.md) still says unchanged argv | Update that file’s command names when this lands, before cache work |

## Out of scope until this works

Daemon-user, cache/sync, stable ids, send/drafts, permission matrix, Homebrew formula, multi-account, list filters.
