# Task: daemon-user install

Hide the IMAP password from the Unix user that agents run as, by splitting olive-mail across two uids. Agents keep calling `olive-mail`. They never handle the credential. The process that *has* the password is the one that enforces policy.

Status: todo  
Date: 2026-09-02  
Depends on: live IMAP already working via `olive-mail auth`  
Platforms: Linux and macOS (same feature, native service manager on each)

This is the privilege split the README already names as required to actually hide the secret. It is a local, same-machine split. Not Keychain, not systemd-creds, not a remote vault, not a Grok Bot connector.

## Why this, and not something else

Unix access control is by **user**, not by **program**.

- A compiled olive-mail cannot keep a password “in itself.” The same uid can `strings` the binary or dump the process.
- There is no POSIX store that only the storing program may read. Files are uid + mode. Kernel keyrings are not attacker-proof against the same uid.
- Process memory is private from *other* processes, not from the same Unix user (ptrace, `/proc/pid/mem`, `LD_PRELOAD`, replace the binary).
- Sandboxing the *agent* would hide the pass file without a second uid, but we do not control how agents are launched. Out of scope.
- macOS Keychain ACL-bound-to-code-signature is a real same-user trick, and was discarded: it makes security “who signed it,” which is a bad fit for an OSS tool people clone and run (trust a bottle, or sign every self-build). Out of scope.
- TPM / Secure Enclave does not help an IMAP app password: the bytes have to leave the chip to AUTH PLAIN. Out of scope.
- Remote secret management (vault, hosted connector, “secret not on this VM”) is a different product. Out of scope.

The OS-correct local answer: **someone who is not the agent can create a uid the agent cannot assume.** That uid runs olive-mail. The agent uid only runs a client.

Compilation is irrelevant to this feature. A bash (or later Rust) daemon as the other uid is the same gate. Rewriting the language is a separate TODO.

## Goal

- Two uids on the box: **agent user** (the human, and every agent) and **olive-mail user** (hidden, no login).
- Agent-facing `olive-mail` is a thin client: connect to the counterpart, print the result. It never sees the password.
- The counterpart (daemon) **is** olive-mail: credential, IMAP/Himalaya, send gate, future permissions, future cache/search. Anything that could bypass the gate lives there.
- One **hard** ceiling per machine (what the daemon allows that agent uid). Not per-agent isolation — all agents are the same uid.
- If a hard split cannot be installed, **detect that, disclaim it, and still install** with today’s `~/.config/olive-mail/<email>.pass` (`0600`). Fallback is first-class. Honest agents still do not handle the password through the CLI, and the send gate still runs; a malicious same-uid agent can still read the file.

## Current

```
agent uid  →  olive-mail (bash)  →  himalaya -c ~/.config/olive-mail/config.toml
                                      passwd.command = cat ~/.config/olive-mail/<email>.pass
```

`.pass` is mode `0600`. Any process as that user can `cat` it and talk to IMAP/SMTP directly. `deny_send` in the wrapper is a suggestion: skip the wrapper, use Himalaya + the file.

## Target

```
agent uid
    │  olive-mail …     (thin client, no secret)
    ▼
unix socket
    │
olive-mail uid (hidden daemon)
    │  password + IMAP config + policy + Himalaya (+ later cache)
    ▼
IMAP
```

Setup is one interactive `sudo` on a capable machine (`olive-mail install` or an `auth` path that offers install). After that, agents do not sudo.

## How the client talks to the daemon

A **Unix domain socket**. That is the normal local client ↔ daemon pattern when they are different uids on the same machine (Docker, `gpg-agent`, cups, local MySQL, …).

The daemon owns the socket file (e.g. `/var/run/olive-mail/olive-mail.sock`). The thin client connects, sends the command (Himalaya-shaped argv is fine), relays stdout/stderr/exit. Who may connect is file mode + group — the same DAC as any other file, which is the point of the extra user.

systemd and launchd both know how to create that socket and hand it to the daemon at start (socket activation). Use that rather than the daemon binding the path itself if the service manager makes it easy.

Not:

- **TCP localhost** — any local process can hit it unless we add a second auth layer. Useless extra surface for a same-machine split.
- **Named pipe / FIFO** — poor fit for request/response and multiple clients.
- **setuid-per-call** — the other classic Unix style; we already picked a long-lived daemon.
- **macOS XPC only** — Apple’s native privilege-helper IPC. A Unix socket still works on Darwin and is the **one** mechanism for Linux + macOS. Do not take an XPC-only path.

Protocol v1: no HTTP, no D-Bus. Connect, send argv, read the result, close. Framing can be as small as “length-prefixed blobs” or a line-oriented request; pick whatever is boring to implement in the current language.

## Hard split vs fallback

Probe the machine. Do not guess from “user is an admin” — a personal Mac admin with Touch ID/password sudo is the **happy path**.

**Hard split** when all of:

1. We can create a uid and a system service (admin/root **once**).
2. After `sudo -k`, `sudo -n true` **fails** — agents cannot sudo without a human.
3. We are not already root in the sense that daily agent processes will be root.

**Fallback** (today’s pass file) when any of:

1. No admin / `useradd` / `sysadminctl` / LaunchDaemon install refused.
2. Passwordless sudo (`sudo -k; sudo -n true` succeeds) — extra user is theater; agent does `sudo -u olivemail`.
3. Agent processes run as root.

On fallback, print a clear disclaimer: the secret is **not** hidden from a malicious same-uid agent; the CLI still keeps honest agents off the raw password and still applies the send gate. Then continue. Do not fail the install.

Same agent-facing commands in both modes.

## Where the logic lives

The gate lives with the secret. A thin privileged “here is Himalaya, go nuts” helper is today’s bypass (`message send` through the helper).

Put the **whole product** on the olive-mail uid:

- hold the credential
- IMAP config that could affect where the password is sent (an agent rewriting `~/.config` to a hostile IMAP host is otherwise a leak)
- Himalaya (implementation detail inside that uid; agents never invoke it)
- send gate and later folder/date/body permissions
- later: canonical cache and search, because already-downloaded mail is still under policy

The agent-user command is only the connection: argv → socket → stdout/stderr/exit. Agents may write their own client; the daemon API **is** the gate.

Keep the daemon boring where possible, but do not leave policy or mail-at-rest on the agent uid “to shrink TCB” if that data is still permissioned.

## Per-agent passwords

Optional later, as **labels for honest agents** (this intern may only search). Not a hard gate.

All agents share the agent uid, so any of them can steal another’s token (file, env, memory) and impersonate it. Do not advertise per-agent secrets as isolation.

Hard enforcement is one ceiling for the box. Until there is a token scheme, that ceiling is the same for every caller on the socket.

## Scenarios

The test: **someone who is not the agent can create a uid the agent cannot assume.** Ownership of the machine is not enough. IT “could” provision is not enough unless they actually do.

### Hard split works

| Setting | Why |
|---|---|
| Coding agents (Grok Build, Claude Code, …) on a person’s own Mac/Linux box | Operator has admin; sudo is interactive; agents cannot pass Touch ID/password. |
| Self-operated personal agents (e.g. OpenClaw on a Mac mini) when the operator is admin | Same. A locked-down company mini with no admin is the other column. |
| Cloud / VPS agents when the client admins the machine and withholds root from the agent | `useradd` + systemd/launchd at provision; agent user has no NOPASSWD. |
| Company fleet **if IT (or an admin employee) actually installs** the extra user and daemon | Package / image / ansible. Agents do not get sudo. |

`olive-mail install` as the workstation user covers the first three when that user can sudo interactively. Company fleet needs an admin install path, not a hope that each employee can `useradd`.

### Hard split does not work (fallback or don’t bother)

| Setting | Why |
|---|---|
| Vendor cloud computer the client does not admin (Grok Bot VM) | Cannot create a uid, **or** the bot can sudo too (NOPASSWD makes the split fake). |
| Employer-granted VM, individual has no admin, nobody provisioned the daemon | Same as Grok Bot, just internal. Company ownership does nothing by itself. |
| Passwordless sudo / agents already root | Extra user is reachable. Probe must choose fallback. |
| “We own the fleet” with no extra user in the image and no admin for the human | Point 3 of the works-list, not done. |

On Grok Bot–like boxes the real next level is “secret not on this VM” (connector / remote olive-mail). That is **not this task**.

## Non-goals

- macOS Keychain, systemd-creds, kernel keyrings, TPM / Secure Enclave
- Remote vault, hosted connector, Grok Bot connector, “self-hosted secret” as a network service
- Sandboxing or launching agents
- Per-agent hard isolation on a shared uid
- Requiring a compiled language
- Changing the agent-facing command name or Himalaya argv shape
- Enabling send
- Implementing the cache ([tasks/Caching.md](Caching.md)) or granular permission *rules* (separate TODOs) — this task only **places** them on the daemon uid when they exist
- GUI user setup (System Settings). Daemon users are CLI-only and hidden.
- TCP localhost, D-Bus, or an XPC-only macOS helper; IPC is a Unix socket on both platforms
- setuid/setgid helper instead of a daemon

## Layout (machine, not git)

### Hard split

```
# agent uid — no secret
olive-mail                         # thin client on PATH (unchanged name)
~/.config/olive-mail/client.toml   # optional: socket path only, if not the default

# olive-mail uid
/var/lib/olive-mail/               # home / state, mode 700, uid olive-mail
  config.toml                      # Himalaya + policy; not the agent’s ~/.config
  <email>.pass                     # mode 0600, uid olive-mail
/var/run/olive-mail/olive-mail.sock
Linux:  systemd system unit (not systemd --user)
macOS:  LaunchDaemon /Library/LaunchDaemons/…
```

Unix socket: daemon uid owns it; the **installing** user (and thus their agents) can connect; other human logins on a shared box should not. Do not use `staff` on macOS (every local user). A dedicated group, installing uid added, mode `660`, is the default.

Hidden user:

- macOS: `_olivemail`, UID &lt; 500, shell `/usr/bin/false`, hidden from the login window (`sysadminctl` / `dscl`). Settings.app is not involved.
- Linux: `olivemail`, nologin, home `/var/lib/olive-mail` (`useradd`).

### Fallback (no split)

Today’s layout, unchanged:

```
~/.config/olive-mail/config.toml
~/.config/olive-mail/<email>.pass    # 0600, agent uid
```

Client detects “no socket / not installed as daemon” and execs Himalaya locally as now.

## Commands

- `olive-mail install` — probe, then hard split or fallback. One sudo on the hard path. Idempotent. Prints which mode it chose and the disclaimer if fallback.
- `olive-mail auth` — writes the password **into whichever store is active** (daemon dir vs `~/.config`). Must not leave a readable copy on the agent uid after a successful hard install.
- `olive-mail …` — if the socket is up, client only; else fallback wrapper (including `deny_send` in-process).
- `olive-mail status` (or `install --status`) — mode, uid, socket, whether `sudo -n` would succeed now. For humans and for docs; not for agents to “fix.”

Uninstall (optional v1): stop service, remove socket; do not delete the extra user without an explicit flag.

## Tasks

### 1. Probe

- [ ] `sudo -k; sudo -n true` — passwordless sudo.
- [ ] Can we create a user and a system service? (try, or check `id` + writable `/Library/LaunchDaemons` / systemd system dir.)
- [ ] Daily uid is root? → fallback.
- [ ] Decide mode; print it. Never claim “secret hidden” on fallback.

### 2. Linux hard install

- [ ] `useradd` system user `olivemail`, nologin, home `/var/lib/olive-mail`.
- [ ] Group for socket access; add the installing user.
- [ ] systemd **system** unit, `User=olivemail`, socket or `RuntimeDirectory=`.
- [ ] State dir `0700`. Password file `0600` that uid only.

### 3. macOS hard install

- [ ] Same, via `sysadminctl` and/or `dscl`: hidden `_olivemail`, UID &lt; 500, no shell.
- [ ] LaunchDaemon plist in `/Library/LaunchDaemons/`, `UserName`, `launchctl bootstrap system`.
- [ ] All terminal. No System Settings.

### 4. Daemon

- [ ] Runs as the olive-mail uid. Reads only *its* config and pass files.
- [ ] Speaks a narrow command API over the socket (Himalaya-shaped argv is fine). Applies `deny_send` **here**. Does not expose “print the password” or a raw shell.
- [ ] Invokes Himalaya (or IMAP) only inside this uid. Agents never call `himalaya` as part of the supported path.
- [ ] IMAP host/credentials live only here so the agent cannot redirect AUTH to a hostile server.

### 5. Thin client

- [ ] Same `olive-mail` on PATH. If socket present and connectable, send argv, relay stdio/exit. Else fallback path (today’s script).
- [ ] No pass file on the agent uid in hard mode. `auth` after install must not write one there (or must remove it).

### 6. Fallback install / `auth`

- [ ] No extra user. Write `~/.config/olive-mail/<email>.pass` as today.
- [ ] Disclaimer on stderr (and once in `status`): not hidden from a malicious same-uid agent; CLI + send gate still apply for normal use.
- [ ] Existing `./olive-mail auth` on a box that never ran `install` stays this mode (backward compatible).

### 7. Docs in this repo

- [ ] README: privilege split when install can; fallback when not; scenarios in short. Remove “theoretically a shell can always read the file” as the only story — say when that is still true.
- [ ] Layout section: both modes.
- [ ] TODO.md: this task checked off when done. Keychain / systemd-creds stay gone.
- [ ] `olive-mail install --help` names the probe and both outcomes.

### 8. Interaction with other TODOs (do not implement here)

- [ ] Caching.md: Maildir must eventually live under the olive-mail uid, not `$XDG_DATA_HOME` of the agent. Note in Caching.md when this ships, or a one-line pointer from that file.
- [ ] Granular permissions: rules engine in the daemon; still one ceiling per machine unless/until cooperative agent labels exist.

## Order

1. Probe + disclaimer (can ship before the daemon; `status` useful immediately)
2. Thin client + fallback path (today’s behavior, explicit mode)
3. Linux daemon + user + systemd
4. macOS daemon + user + LaunchDaemon
5. `auth` writes to the active store; drop agent-uid `.pass` on hard install
6. README

## Done when

- On a personal Linux or macOS box with interactive sudo: extra user exists, socket works, `.pass` is **not** readable by the agent uid, `olive-mail envelope list` still works, `message send` is still rejected **by the daemon**.
- `cat` of any agent-uid olive-mail file does not yield the IMAP password.
- Direct `himalaya` as the agent uid cannot AUTH (no pass file, no Keychain, no helper that prints the secret).
- On a box with `NOPASSWD` sudo or no admin: install chooses fallback, prints the disclaimer, and today’s path still works.
- Same feature on Linux and macOS.
- No Keychain, no systemd-creds, no remote secret path in this work.

## Risks

| Risk | Mitigation |
|---|---|
| Passwordless sudo / docker-group / already-root makes split fake | Probe `sudo -k; sudo -n true`; refuse to *claim* isolation; fallback |
| Cached sudo timestamp during `install` looks like NOPASSWD | Always `sudo -k` before `-n` |
| Agent rewrites IMAP host and steals AUTH | Config + password only on olive-mail uid |
| Socket world-connectable on a shared Mac (`staff`) | Dedicated group; only installing uid |
| setuid helper instead of daemon | Don’t; LaunchDaemon/systemd. Smaller, long-lived TCB, no setuid |
| Himalaya still `cat`s a file the agent can see | File not in agent home; `passwd.command` only in daemon config |
| Fallback users think they got the hard split | Loud disclaimer; `status` shows mode |
| Caching.md puts Maildir in agent XDG | Pointer when this lands; cache follows the daemon |
| Company IT never runs `useradd` | Admin/package path in docs; workstation `install` is not that path |
| macOS GUI-only intuition | Document CLI-only hidden user; never send people to System Settings |
