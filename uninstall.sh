#!/usr/bin/env bash
#
# uninstall.sh — remove the `server` symlink and the ~/.zshrc block.
# The project directory itself is left intact.

set -euo pipefail

readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BIN_DIR="${HOME}/.local/bin"
readonly ZSHRC="${HOME}/.zshrc"
readonly MARKER_START='# >>> server-cli >>>'
readonly MARKER_END='# <<< server-cli <<<'

main() {
  # Remove the symlink only if it points at this project.
  if [[ -L "$BIN_DIR/server" ]] && [[ "$(readlink "$BIN_DIR/server")" == "$PROJECT_DIR/server" ]]; then
    rm "$BIN_DIR/server"
    echo "removed: $BIN_DIR/server"
  fi

  # Remove the marker block from ~/.zshrc (string match, not regex).
  if [[ -f "$ZSHRC" ]] && grep -qF -- "$MARKER_START" "$ZSHRC"; then
    local tmp="${ZSHRC}.tmp.$$"
    awk -v s="$MARKER_START" -v e="$MARKER_END" '
      index($0, s) { skip = 1; next }
      index($0, e) { skip = 0; next }
      !skip { print }
    ' "$ZSHRC" > "$tmp"
    mv "$tmp" "$ZSHRC"
    echo 'removed server-cli block from ~/.zshrc'
  fi

  echo "Uninstalled. Project kept at $PROJECT_DIR — delete it manually if you want."
}

main "$@"
