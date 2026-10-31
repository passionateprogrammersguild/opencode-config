#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[info]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
error() { echo -e "${RED}[error]${NC} $*"; exit 1; }

# Resolve script directory (works even if called via symlink)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR"
CONFIG_DST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

# ---------------------------------------------------------------------------
# 1. Check / install OpenCode and enforce 2.x
# ---------------------------------------------------------------------------
check_or_install_opencode() {
  if command -v opencode >/dev/null 2>&1; then
    local version
    version=$(opencode --version 2>/dev/null || true)

    if [[ -z "$version" ]]; then
      error "Found 'opencode' but could not read version. Aborting."
    fi

    info "Found OpenCode: $version"

    # Accept anything that starts with 2. (2.0, 2.0.26, v2.0.1, etc.)
    if [[ "$version" =~ ^v?2\. ]]; then
      info "OpenCode 2.x confirmed – good."
    else
      error "OpenCode is installed but is not version 2.x (got: $version).
This config repo requires OpenCode 2.0+.
Please upgrade or uninstall the old version and re-run this script."
    fi
  else
    info "OpenCode not found. Installing OpenCode 2.0..."
    curl -fsSL https://opencode.ai/v2/install | bash

    # Make sure the new binary is on PATH for the rest of this script
    export PATH="$HOME/.opencode/bin:$PATH"

    if ! command -v opencode >/dev/null 2>&1; then
      error "Installation appeared to succeed but 'opencode' is still not on PATH.
Try opening a new terminal and re-running this script."
    fi

    local new_version
    new_version=$(opencode --version 2>/dev/null || true)
    info "Installed OpenCode: $new_version"

    if [[ ! "$new_version" =~ ^v?2\. ]]; then
      error "Installed version is not 2.x (got: $new_version). Something went wrong."
    fi
  fi
}

# ---------------------------------------------------------------------------
# 2. Install / update config
# ---------------------------------------------------------------------------
install_config() {
  info "Installing config into $CONFIG_DST"

  mkdir -p "$CONFIG_DST"

  # Files / dirs we want to copy from the repo
  local items=(
    opencode.json
    opencode.jsonc
    cli.json
    cli.jsonc
    AGENTS.md
    agents
    commands
    skills
    plugins
  )

  for item in "${items[@]}"; do
    local src="$CONFIG_SRC/$item"
    local dst="$CONFIG_DST/$item"

    if [[ -e "$src" ]]; then
      if [[ -d "$src" ]]; then
        # Directory: merge (rsync is nice if available)
        if command -v rsync >/dev/null 2>&1; then
          rsync -a --delete "$src/" "$dst/"
        else
          rm -rf "$dst"
          cp -a "$src" "$dst"
        fi
        info "  → $item/ (directory)"
      else
        cp -a "$src" "$dst"
        info "  → $item"
      fi
    fi
  done

  info "Config installed successfully."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo
  info "OpenCode Config Installer"
  echo

  check_or_install_opencode
  echo
  install_config

  echo
  info "Done!"
  info "Run 'opencode' in any project to start."
  echo
}

main "$@"