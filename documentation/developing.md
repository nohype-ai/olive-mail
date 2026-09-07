# Developing `olive-mail`

- How we go about making a CLI with Swift: https://github.com/nohype-ai/NohypeAIStack/blob/main/stack/apple/Swift%20CLI%20Development.md

## This repo

- Open work is [TODO.md](TODO.md). Designs live in [tasks/](tasks/). Implement the task file; don’t invent a parallel API.
- Same agent commands, stronger guts. Cache, permissions, redaction, and the daemon-user split are not new verbs, not an MCP, not a second binary.
- New capability: our flag/command + a `MailBackend` method. Himalaya mapping stays in `HimalayaBackend`. The parser never execs Himalaya.
- Commented flags and types are the reserved next surface. Uncomment and fill them in; don’t rename the job.
- Send stays absent until a task explicitly adds a gate. Himalaya being able to send is not a reason.
- `swift test` / `swift run`. Parse tests (`commandExists` / `commandDoesNotExist`) are the API lock — change them with the surface.
- Backend tests mock Himalaya JSON. No live IMAP. No real mailbox in the repo or tests.
- Credentials only under `~/.config/olive-mail/`, never committed. Don’t auto-install Himalaya.
- Linux and macOS, same config paths. Don’t take a Darwin-only security shortcut.
- New commands: flags in, result out. TTY prompts only for collecting a secret.
