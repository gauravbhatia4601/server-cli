#!/usr/bin/env bash
#
# install — link `server` onto PATH and enable zsh completion.
# Idempotent: safe to run again.

set -euo pipefail

readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BIN_DIR="${HOME}/.local/bin"
readonly ZSHRC="${HOME}/.zshrc"
readonly MARKER_START='# >>> server-cli >>>'
readonly MARKER_END='# <<< server-cli <<<'

main() {
  # 1. Symlink into a directory already on PATH (no PATH edits needed).
  mkdir -p "$BIN_DIR"
  ln -sfn "$PROJECT_DIR/server" "$BIN_DIR/server"
  echo "linked: $BIN_DIR/server -> $PROJECT_DIR/server"

  # 2. Register completion + compinit in ~/.zshrc (once).
  if grep -qF -- "$MARKER_START" "$ZSHRC" 2>/dev/null; then
    echo '~/.zshrc already configured (no changes).'
  else
    cat >> "$ZSHRC" <<EOF

${MARKER_START}
fpath=(${PROJECT_DIR}/completions \$fpath)
autoload -Uz compinit && compinit
${MARKER_END}
EOF
    echo 'added completion setup to ~/.zshrc (open a new terminal to enable)'
  fi

  echo 'Done. Try: server list'
}

main "$@"
