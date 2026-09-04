# Task: daemon-user install

Hide the IMAP password from the Unix user that agents run as, by splitting olive-mail across two uids. Agents keep calling `olive-mail`. They never handle the credential. The process that *has* the password is the one that enforces policy.

Status: todo  
Date: 2026-09-03  
Depends on:

- live IMAP already working via `olive-mail auth`
- **compiled olive-mail (Swift) as a separate task, done first** — this file is not that rewrite. The extra uid is what hides the secret; a real language is what makes the daemon a program we can trust to implement it. Do not start this install/daemon work in bash.

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

The daemon is a small **server** (long-lived, many sessions, a wire protocol, it is the TCB). That is why the language rewrite comes first. Compilation still does not hide the password.

> Side note for clarity: Even though a shared human/agent uid might have admin rights, any action that actually requires admin rights (adding another user account, running something as another user) actually triggers an authentication request by the OS (Touch ID / passssword), **if** passwordless sudo is not available. That's why this works. Agents can trigger the request but not complete it (they obviously must not have the user's password).

## Goal

- Two uids: **agent user** (the human *and* every agent — there is no third “human only” uid) and **olive-mail user** (hidden, no login). The olive-mail **program** runs entirely as that second uid. Agent-facing `olive-mail` is only a thin client (connect, print).
- IPC is a **Unix socket**, never TCP localhost / MCP / HTTP / XPC.
- Hard gate is a **permission matrix per Unix user** (peer uid the kernel attests). Default: installing uid may use mail under the ceiling (no send); everyone else can connect and is denied (logged).
- Matrix **edits** never go over the agent-facing socket. A CLI admin path hops to the olive-mail uid via OS authentication (sudo / polkit / Touch ID). No password, no standing admin session, in any agent-uid process.
- If a hard split cannot be installed, **detect that, disclaim it, and still install** with today’s `~/.config/olive-mail/<email>.pass` (`0600`). Fallback is first-class.

## Current

```
agent uid  →  olive-mail (bash)  →  himalaya -c ~/.config/olive-mail/config.toml
                                      passwd.command = cat ~/.config/olive-mail/<email>.pass
```

`.pass` is mode `0600`. Any process as that user can `cat` it and talk to IMAP/SMTP directly. `deny_send` in the wrapper is a suggestion: skip the wrapper, use Himalaya + the file.

## Target

```
agent uid
    │  olive-mail …          thin client, mail ops only
    ▼
unix socket (world-connectable; identity = peer uid)
    │
olive-mail uid (daemon = the whole program)
    │  password + IMAP config + matrix + Himalaya (+ later cache)
    ▼
IMAP

agent uid
    │  olive-mail permit …   does NOT use that socket
    ▼
OS prompt (sudo / polkit / Touch ID)
    ▼
short helper as olive-mail uid → writes matrix → exits
```

Setup is one interactive `sudo` on a capable machine (`olive-mail install`). After that, agents do not sudo. Humans sudo again only to change the matrix (or re-install).

## How the client talks to the daemon

A **Unix domain socket**. Normal local client ↔ daemon when they are different uids (Docker, `gpg-agent`, cups, local MySQL).

The path (e.g. `/var/run/olive-mail/olive-mail.sock`) is only the doorbell. Each `connect`/`accept` is its own session (own fd, own peer uid). Many clients in parallel is the normal case. The daemon must not mix their traffic; serialize work that isn’t safe to overlap (e.g. one Himalaya if that’s the constraint).

**Who connected:** `SO_PEERCRED` (Linux) / `LOCAL_PEERCRED` (macOS). The kernel attests uid. That is the matrix key. No token.

**Who may connect:** the socket is **world-connectable** (`666`). The directory is **not** world-writable (`/var/run/olive-mail/` `755`, owned by the daemon or root) so nobody can replace the socket and MITM. Authorization is the matrix inside olive-mail, not a socket group.

systemd / launchd socket activation if it is easy; otherwise the daemon binds the path.

Not:

- **TCP localhost** — does *not* undo the extra-user split (password still in the other uid). It does drop filesystem DAC and kernel peer-uid, so you’d invent tokens and you can bind `0.0.0.0` by mistake. Out. Unix socket gives peer uid for free.
- **Named pipe / FIFO** — poor fit for request/response and multiple clients.
- **setuid-per-call** — the other classic Unix style; we picked a daemon.
- **XPC** — macOS-only. Out. Unix socket on Darwin too.

Protocol v1: no HTTP, no D-Bus, no MCP. Connect, send argv, read the result, close. MCP, if ever, is a later **client** of this socket, not the privileged API.

The agent-facing socket speaks **mail operations only**. It does not speak permit / policy-write / unlock / admin. A client that sends those is rejected.

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

Same agent-facing mail commands in both modes. `permit` only exists in hard-split mode (there is no olive-mail uid to hop to).

## Where the logic lives

The gate lives with the secret. A thin privileged “here is Himalaya, go nuts” helper is today’s bypass.

Put the **whole product** on the olive-mail uid (the TCB: code that can leak the password or skip the gate):

- hold the credential
- IMAP config (an agent rewriting a user-level config to a hostile IMAP host would steal AUTH)
- Himalaya only inside this uid
- permission matrix + send gate
- later: canonical cache and search

Keep that process **small**. No GUI toolkit in the daemon. No HTML. A GUI, if ever, is a separate agent-uid viewer; this task has no GUI.

The agent-uid binary is only the connection for mail, and the **launcher** for admin (it triggers OS auth; it does not become admin).

## Permission matrix (hard gate)

Identity = **Unix uid** of the connecting process. All agents as that user share one row. That is the only hard isolation the OS will enforce.

v1 matrix:

- rows: Unix users
- columns: at least `use` (list/read/search) vs `send` (always off in v1)
- default: **installing uid** may `use`, not `send`. Every other uid: deny, **log** (uid, time, command).
- stored only under `/var/lib/olive-mail/` (`700` / files `600`, olive-mail uid)

Later granular rules (folders, dates, metadata vs body) are a separate TODO; they land in this same matrix, still keyed by uid.

**Agent IDs** (cooperative labels, “this intern only searches”): out of scope. Same uid can steal another’s id. Nice later for monitoring honest agents, not a gate, not this task.

## Admin path (CLI, not the agent socket)

There is no third human uid. The human *is* the agent uid at the keyboard. So “GUI/CLI as the agent user can edit policy after a password” is a hole: the secret or an admin session sits in a process the agents are.

**Do not:**

- put permit / unlock / matrix-write on the world socket
- collect the mailbox password, sudo password, or a standing admin ticket in an agent-uid process
- write a temp policy file then `sudo apply /tmp/...` (agents can swap the file)

**Do:** matrix files are only writable by the olive-mail uid. The human reaches that uid the same way as `install`: OS authentication, then a **short-lived helper as `_olivemail` / `olivemail`**.

CLI analogue (this task; no GUI):

```
olive-mail permit alice use
olive-mail permit alice deny
olive-mail permit --file matrix.toml   # whole matrix, one apply
olive-mail policy                      # show matrix (see below)
```

The human may take as long as they want to **prepare** a file (or a GUI draft). That file lives in the agent uid; agents can mess with a draft. That is fine: it is not live.

**Apply** is one command, **one** OS prompt, and can push the whole prepared matrix. `permit alice use` is the small form; `--file` is the batch form.

`permit` does not connect as admin. The client **reads the payload first** (argv, or the file into memory / an already-open fd), then `exec`s `sudo` / `polkit` / macOS authorization (Touch ID). The OS prompts. The helper runs as the olive-mail uid, reads that **payload on stdin** (not a path it opens itself — agents must not get a TOCTOU swap on `/tmp/matrix.toml` after auth), writes `/var/lib/olive-mail/…`, exits. Daemon reloads (signal, inotify, or next request).

**Every `permit` authenticates.** No unlock-and-keep, no `auth_admin_keep`, no leftover sudo timestamp. After the helper, `sudo -k` (or polkit `auth_admin`, not `auth_admin_keep`). Touch ID per apply is the intended UX: serious, simple, good enough. A future GUI uses the same rule (no Settings-style Unlock for a session of edits).

Until that helper succeeds, the live matrix is unchanged. Agents can run `olive-mail permit` all day; they fail the OS prompt (unless passwordless sudo — already fallback).

`policy` show: either the helper (sudo) reads the file, or the daemon may **read**-report the caller’s own row (and the owner’s full matrix) on the mail socket. Writes never go that way.

A future GUI would be the same principle: agent-uid viewer, Commit = this helper. Not in this task.

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
- Per-agent hard isolation; agent IDs / cooperative labels
- The Swift/compiled rewrite itself (precondition, separate TODO)
- GUI (viewer or editor). Admin is CLI + OS prompt. Daemon stays without a GUI.
- Admin / unlock / permit on the agent-facing socket; standing admin sessions in the agent uid
- Using the IMAP password as an admin factor
- TCP localhost, D-Bus, MCP-as-privileged-API, or XPC
- setuid/setgid helper as the *mail* path (the admin hop is sudo/polkit, one shot, not a setuid mail daemon)
- Changing the agent-facing mail command name or Himalaya argv shape
- Enabling send
- Implementing the cache ([tasks/Caching.md](Caching.md)) or granular permission *rules* (separate TODOs) — this task **places** a per-uid matrix and the admin hop; richer columns come later
- Creating users via System Settings. Daemon users are CLI-only and hidden.

## Layout (machine, not git)

### Hard split

```
# agent uid — no secret, no policy file
olive-mail                         # thin client + admin launcher on PATH
~/.config/olive-mail/client.toml   # optional: socket path only

# olive-mail uid — whole program
/var/lib/olive-mail/               # 700, uid olive-mail
  config.toml                      # Himalaya; not the agent’s ~/.config
  <email>.pass                     # 0600, uid olive-mail
  policy                           # matrix, 0600, uid olive-mail
/var/run/olive-mail/               # 755, daemon or root; NOT world-writable
  olive-mail.sock                  # 666, world-connectable

Linux:  systemd system unit (not systemd --user)
macOS:  LaunchDaemon /Library/LaunchDaemons/…
```

Hidden user:

- macOS: `_olivemail`, UID &lt; 500, shell `/usr/bin/false`, hidden from the login window (`sysadminctl` / `dscl`). Settings.app is not involved.
- Linux: `olivemail`, nologin, home `/var/lib/olive-mail` (`useradd`).

### Fallback (no split)

Today’s layout, unchanged:

```
~/.config/olive-mail/config.toml
~/.config/olive-mail/<email>.pass    # 0600, agent uid
```

Client detects “no socket / not installed as daemon” and runs the local fallback (send gate in-process). No `permit`.

## Commands

- `olive-mail install` — probe, then hard split or fallback. One sudo on the hard path. Records the installing uid as the first matrix row (`use`, no send). Idempotent. Prints which mode it chose and the disclaimer if fallback.
- `olive-mail auth` — writes the password **into whichever store is active** (daemon dir vs `~/.config`). Must not leave a readable copy on the agent uid after a successful hard install. Auth is not the admin path; it still needs a human factor so agents cannot rotate the secret (interactive prompt / sudo as appropriate).
- `olive-mail …` (mail) — if the socket is up, client only, matrix applied by **peer uid**. Else fallback wrapper.
- `olive-mail permit <user> use|deny` — one OS prompt, helper as olive-mail uid, stdin/argv payload, no public socket.
- `olive-mail permit --file <path>` — client reads the file first, then the same one-shot apply (full matrix).
- `olive-mail policy` — show matrix (sudo helper and/or read-only report).
- `olive-mail status` — mode, uid, socket, whether `sudo -n` would succeed now. For humans; not for agents to “fix.”

Uninstall (optional v1): stop service, remove socket; do not delete the extra user without an explicit flag.

## Tasks

### 1. Probe

- [ ] `sudo -k; sudo -n true` — passwordless sudo.
- [ ] Can we create a user and a system service?
- [ ] Daily uid is root? → fallback.
- [ ] Decide mode; print it. Never claim “secret hidden” on fallback.

### 2. Linux hard install

- [ ] `useradd` system user `olivemail`, nologin, home `/var/lib/olive-mail`.
- [ ] systemd **system** unit, `User=olivemail`, `RuntimeDirectory=` `755`.
- [ ] Socket `666` in that dir. State dir `0700`. Pass + policy `0600`.
- [ ] Matrix: installing uid `use`, not `send`.

### 3. macOS hard install

- [ ] Hidden `_olivemail`, UID &lt; 500, no shell (`sysadminctl` / `dscl`).
- [ ] LaunchDaemon plist in `/Library/LaunchDaemons/`, `UserName`, `launchctl bootstrap system`.
- [ ] Same socket/state/matrix rules. All terminal. No System Settings.

### 4. Daemon (olive-mail uid — the program)

- [ ] Reads only *its* config, pass, policy.
- [ ] Accept many sessions. Identity = peer uid. Apply matrix. Log denies.
- [ ] Mail API only (Himalaya-shaped argv is fine). `deny_send` here. Reject permit/unlock/admin. Never print the password.
- [ ] Himalaya / IMAP only inside this uid. IMAP host + credentials only here.
- [ ] Reload policy after helper write.

### 5. Thin client (agent uid)

- [ ] Same `olive-mail` on PATH. Mail subcommands: socket if present, else fallback.
- [ ] `permit` / `policy` write: do **not** use the mail socket; invoke the OS-auth helper.
- [ ] No pass file on the agent uid in hard mode.

### 6. Admin helper

- [ ] Tiny binary/entry: runs as olive-mail uid via sudo/polkit/Touch ID, not setuid-mail.
- [ ] Payload on stdin (or fixed argv: uid + verb). Never `apply /tmp/policy`.
- [ ] Writes `policy`, exits. No long-lived admin session.
- [ ] Per-`permit` OS prompt: polkit `auth_admin` (not `_keep`); `sudo -k` after; macOS prompt every apply.
- [ ] GUI-free. This *is* the management API for v1.

### 7. Fallback install / `auth`

- [ ] No extra user. Write `~/.config/olive-mail/<email>.pass` as today.
- [ ] Disclaimer on stderr (and `status`).
- [ ] Existing `./olive-mail auth` without `install` stays this mode.

### 8. Docs in this repo

- [ ] README: privilege split when install can; fallback when not; per-uid matrix; `permit` uses OS auth. When a same-uid agent can still read the file (fallback).
- [ ] Layout: both modes.
- [ ] TODO.md: this task checked off when done. Keychain / systemd-creds stay gone.
- [ ] `olive-mail install --help` / `permit --help` name the probe, both outcomes, and that permit is not the mail socket.

### 9. Interaction with other TODOs (do not implement here)

- [ ] Caching.md: Maildir under the olive-mail uid, not agent `$XDG_DATA_HOME`.
- [ ] Granular permissions: more matrix columns in the daemon; still keyed by uid.
- [ ] Agent IDs / GUI viewer: later, same admin helper on Commit.

## Order

1. Language rewrite (separate task) — blocked until then
2. Probe + disclaimer
3. Thin client + fallback path
4. Linux daemon + user + systemd + matrix
5. macOS daemon + user + LaunchDaemon
6. Admin helper (`permit`)
7. `auth` writes to the active store; drop agent-uid `.pass` on hard install
8. README

## Done when

- On a personal Linux or macOS box with interactive sudo: extra user exists, world socket works, `.pass` is **not** readable by the agent uid, `olive-mail envelope list` works for the installing uid, a second Unix user is denied and logged, `message send` is rejected **by the daemon**.
- `olive-mail permit` triggers an OS auth prompt; without it the matrix does not change; a successful permit as the helper uid does.
- No admin/unlock on the mail socket. No password prompt in the agent-uid client except OS sudo/polkit/Touch ID.
- Direct `himalaya` as the agent uid cannot AUTH.
- On a box with `NOPASSWD` sudo or no admin: fallback + disclaimer; today’s path still works.
- Same feature on Linux and macOS. No GUI. No Keychain, systemd-creds, TCP, or remote secret path.

## Risks

| Risk | Mitigation |
|---|---|
| Passwordless sudo / docker-group / already-root makes split fake | Probe `sudo -k; sudo -n true`; fallback; never claim isolation |
| Cached sudo timestamp during `install` looks like NOPASSWD | Always `sudo -k` before `-n` |
| Agent rewrites IMAP host and steals AUTH | Config + password only on olive-mail uid |
| Agent replaces the socket | Dir `755` not world-writable |
| Permit on the mail socket / admin session in agent uid | Mail API rejects those; helper is the only writer |
| GUI or client password field | None. OS prompt only |
| `sudo apply /tmp/policy` TOCTOU | Helper reads stdin/argv, writes the real path itself |
| Sudo/polkit “keep” after a human `permit` | Not used. Per-apply auth; `sudo -k` / `auth_admin`; Touch ID every time |
| World socket, other humans on the box | Default deny + log; only installing uid has `use` until `permit` |
| Himalaya still `cat`s a file the agent can see | File not in agent home |
| Fallback users think they got the hard split | Loud disclaimer; `status` shows mode |
| Caching.md puts Maildir in agent XDG | Pointer when this lands |
| Company IT never runs `useradd` | Admin/package path in docs |
| macOS GUI-only intuition for *users* | CLI-only hidden user; never System Settings |
| Implementing this in bash | Blocked on the Swift task |
