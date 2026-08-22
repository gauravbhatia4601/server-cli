# server-cli

A tiny, zero-dependency CLI to launch SSH sessions from your `~/.ssh/config`
aliases — fuzzy matching, an interactive picker, and safe server management.
Written in pure bash (compatible with macOS's system bash 3.2 and Linux bash 4+).

## Install

```bash
cd ~/projects/server-cli
./install.sh        # symlinks `server` into ~/.local/bin (already on PATH)
                    # + enables zsh tab-completion
```

Open a new terminal — `server` is now a permanent command.

Uninstall (leaves the project dir intact):

```bash
./uninstall.sh
```

## Usage

```
server [pattern]    connect — exact match wins, else fuzzy, else picker
server list         list all aliases
server info <name>  show HostName / User / Port / keys for one server
server add          add a new server (guided, validates + previews)
server rm <name>    remove a server (preview + confirm + backup)
server edit [name]  open ~/.ssh/config in $EDITOR (optionally at <name>)
server help         help
server version      version
```

Examples:

```sh
server              # pick from all servers
server IGL-Prod     # exact match → straight in
server hatta        # 5 matches → numbered picker
server add          # guided: alias, host, user, port, key
server rm HattaSky  # shows the block, asks, then removes with backup
server edit IGL-Prod # open config, cursor at IGL-Prod's block
```

Tab-completion: `server <TAB>` lists subcommands + all aliases; `server rm <TAB>` lists aliases.

## How it's built (efficiency notes)

- **Single-pass awk** parses `~/.ssh/config` once per invocation — no loops over the file, no repeated greps.
- **`exec` for ssh/editor** — the CLI replaces itself; no child processes, exit codes propagate.
- **`LC_ALL=C` scoped per grep/awk** (~10x faster byte matching), never exported, so `ssh` never inherits it.
- **No subshell loops** — array copies, `printf`/`read` builtins, no `cat | grep` chains.
- **Safe writes** — `rm` writes a temp file, `chmod 600`, atomic `mv`, and keeps `~/.ssh/config.server.bak`.
- **Strict mode** (`set -euo pipefail`), `local` everywhere, `main()` dispatch, errors to stderr.
- Bash 3.2 constraint: no `mapfile`/assoc-arrays/namerefs — deliberately avoided.

## Env knobs

| Variable | Default | Purpose |
|---|---|---|
| `SERVER_SSH_CONFIG` | `~/.ssh/config` | ssh config path |
| `SERVER_SSH` | `ssh` | ssh binary (used by tests) |

## Tests

```sh
bash tests/run.sh    # 28 checks; uses a throwaway config + fake ssh
```

## Roadmap

- fzf picker when available (falls back to numbered prompt)
- tags / groups, `server rename`, connect history
