# Roadmap

`server` is a zero-dependency, bash-3.2-compatible SSH launcher. The guiding
principle: **stay the lightest possible tool** — no runtime deps, no daemon,
symlink-to-install. Features that need a compiled TUI (embedded PTY, SFTP
browser, live dashboards) are deliberately out of scope; use `sshc`, `sshelf`
or `purple` for those.

## v0.3 — Discovery & quality of life ✅ (current)

- [x] `server search <term>` — search alias + hostname + user
- [x] `server list` — richer columns (`alias  user@host:port`)
- [x] `server -` — reconnect to the last-used server
- [x] `server ping <name>` — TCP reachability probe (`/dev/tcp`, no deps)

## v0.4 — Organization

- [ ] Tags via comments (`# @tags: prod,web`) → `server @prod`
- [ ] Favorites / pinning
- [ ] `server rename <old> <new>`
- [ ] `server copy <name>` (duplicate a host block)

## v0.5 — Power (still bash-appropriate)

- [ ] `server exec <host> -- <cmd>` — run a command, return its exit code
- [ ] `server copy-id <host>` — push your public key
- [ ] `--json` on `list` / `info` for scripting
- [ ] `server doctor` — environment diagnostics

## v0.6 — Distribution & polish

- [ ] Homebrew tap
- [ ] bash completion (currently zsh-only)
- [ ] man page
- [ ] GitHub Actions CI running the test suite on macOS + Linux

## Explicitly out of scope

- Full TUI / embedded PTY / SFTP browser / live dashboards (needs Rust/Go)
- Encrypted password vault (risky in bash; compiled languages do it safely)
- Cloud-provider sync
