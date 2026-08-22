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
server -            reconnect to the last-used server
server list         list servers (alias + user@host:port + tags/group)
server search <t>   search aliases, hostnames and users
server ping <name>  TCP reachability probe
server @<tag>       list hosts with a tag
server @group:<g>   list hosts in a group
server tags         list all tags
server groups       list all groups
server tag           interactive: pick/create a tag, then pick a host
server tag <tag>     list hosts with a tag
server tag <h> <t>   add a tag to a host
server untag <h> <t> remove a tag from a host
server group         interactive: pick/create a group, then pick a host
server group <name>  list hosts in a group
server group <h> <g> set a host's group
server ungroup <h>   remove a host from its group
server info <name>  show HostName / User / Port / keys for one server
server add          add a new server (guided, validates + previews)
server rm <name>    remove a server (preview + confirm + backup)
server edit [name]  open ~/.ssh/config in $EDITOR (default: nano), optionally at <name>
server help         help
server version      version
```

Examples:

```sh
server              # pick from all servers
server IGL-Prod     # exact match → straight in
server hatta        # 5 matches → numbered picker
server -            # reconnect to whatever you used last
server search 40.17 # find by IP/hostname/user, not just alias
server ping IGL-Prod # is it up? (TCP probe, no deps)
server tag IGL-Prod prod   # tag a host (short form)
server group IGL-Prod prod # set a host's group (short form)
server tag           # interactive: pick/create tag → pick host
server group         # interactive: pick/create group → pick host
server ungroup IGL-Prod  # remove a host from its group
server @prod        # list hosts tagged prod
server @group:prod  # list hosts in group prod
server tags         # list all tags
server add          # guided: alias, host, user, port, key
server rm HattaSky  # shows the block, asks, then removes with backup
server edit IGL-Prod # open config, cursor at IGL-Prod's block
```

### Tags & groups

Tags and groups live in comments directly above a `Host` block:

```sshconfig
# @tags: prod, web
# @group: production
Host IGL-Prod
  HostName 40.172.145.167
  User ubuntu
```

`server tag <host> <tag>` / `server group <host> <name>` write these for you;
`server @<tag>` / `server @group:<name>` filter by them.

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
| `SERVER_STATE_FILE` | `~/.config/server-cli/state` | last-connection state |

## Tests

```sh
bash tests/run.sh    # 99 checks; uses a throwaway config + fake ssh
```

## Roadmap

See [ROADMAP.md](ROADMAP.md).
