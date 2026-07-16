#!/data/data/com.termux/files/usr/bin/sh
set -eu

# OpenCode Termux uninstaller.
#
# Removes the opencode launcher, the patched ELF binary, and the npm
# packages installed by install-opencode-termux.sh. By default, user data
# under ~/.local/share/opencode (logs, sessions, repos) is preserved.
#
# VERSION FREEZE
#   This uninstaller is frozen for opencode-ai 1.18.2 (the same build
#   installed by install-opencode-termux.sh). It will not silently target
#   a different upstream version. The actual freeze check lives below,
#   right after `fail()` is defined.

FROZEN_VERSION="1.18.2"
PLATFORM_PKG="opencode-linux-arm64"
REMOVE_USER_DATA="${REMOVE_USER_DATA:-0}"
FORCE="${FORCE:-0}"

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.local/share/opencode}"
BINARY="$INSTALL_DIR/bin/opencode"
WRAPPER="$PREFIX/bin/opencode"

NPM_PREFIX="$(npm root -g)"

STEP_INDEX=0
STEP_TOTAL=7

display_path() {
  case "$1" in
    */.local/share/opencode/*) printf '%s\n' ".../share/opencode/${1##*/share/opencode/}" ;;
    /data/data/com.termux/files/*) printf '%s\n' ".../${1#/data/data/com.termux/files/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

banner() {
  cat <<EOF

+------------------------------------------------------------+
| OpenCode for Termux                                       |
| Uninstaller                                               |
+------------------------------------------------------------+
EOF
  printf '| %-58s |\n' "Target version : $VERSION"
  printf '| %-58s |\n' "Install path   : $(display_path "$BINARY")"
  printf '| %-58s |\n' "Launcher       : $(display_path "$WRAPPER")"
  if [ "$REMOVE_USER_DATA" = "1" ]; then
    printf '| %-58s |\n' "User data      : will be removed"
  else
    printf '| %-58s |\n' "User data      : preserved"
  fi
  cat <<EOF
+------------------------------------------------------------+

EOF
}

step() {
  STEP_INDEX=$((STEP_INDEX + 1))
  printf '\n[%02d/%02d] %s\n' "$STEP_INDEX" "$STEP_TOTAL" "$*"
}

ok() {
  printf '%s\n' "         done: $*"
}

warn() {
  printf '%s\n' "Warning: $*" >&2
}

fail() {
  printf '%s\n' "Error: $*" >&2
  exit 1
}

if [ -n "${VERSION:-}" ] && [ "$VERSION" != "$FROZEN_VERSION" ]; then
  fail "This uninstaller is frozen for opencode-ai $FROZEN_VERSION. The VERSION env var is set to '$VERSION', but the supported value is '$FROZEN_VERSION'."
fi
VERSION="$FROZEN_VERSION"

complete_banner() {
  cat <<EOF

+------------------------------------------------------------+
| Uninstallation complete                                   |
+------------------------------------------------------------+
EOF
  printf '| %-58s |\n' "OpenCode $VERSION has been removed."
  if [ "$REMOVE_USER_DATA" = "1" ]; then
    printf '| %-58s |\n' "User data at $(display_path "$INSTALL_DIR") was also removed."
  else
    printf '| %-58s |\n' "User data at $(display_path "$INSTALL_DIR") was preserved."
  fi
  cat <<EOF
+------------------------------------------------------------+

EOF
}

# ---- preflight --------------------------------------------------------------

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) fail "Unsupported architecture: $(uname -m). This uninstaller supports Termux aarch64/arm64 only." ;;
esac

case "$PREFIX" in
  */com.termux/files/usr) ;;
  *) warn "PREFIX is set to $PREFIX. This uninstaller is intended for Termux." ;;
esac

banner

# ---- steps ------------------------------------------------------------------

step "Removing npm packages"
if command -v npm >/dev/null 2>&1; then
  if [ -d "$NPM_PREFIX/opencode-ai" ]; then
    npm uninstall -g opencode-ai >/dev/null 2>&1 || warn "Failed to remove opencode-ai via npm (continuing)."
    ok "opencode-ai npm package removed."
  else
    ok "opencode-ai npm package not present."
  fi
  if [ -d "$NPM_PREFIX/$PLATFORM_PKG" ]; then
    npm uninstall -g "$PLATFORM_PKG" >/dev/null 2>&1 || warn "Failed to remove $PLATFORM_PKG via npm (continuing)."
    ok "$PLATFORM_PKG npm package removed."
  else
    ok "$PLATFORM_PKG npm package not present."
  fi
else
  warn "npm is not available; skipping npm-based removal."
  ok "Skipped npm cleanup."
fi

step "Removing launcher"
if [ -L "$WRAPPER" ] && [ "$FORCE" != "1" ]; then
  warn "Launcher at $WRAPPER is a symlink not created by this installer. Skipping removal (set FORCE=1 to remove anyway)."
elif [ -e "$WRAPPER" ] || [ -L "$WRAPPER" ]; then
  rm -f "$WRAPPER"
  ok "Launcher removed: $WRAPPER"
else
  ok "Launcher not present."
fi

step "Removing patched ELF binary"
if [ -e "$BINARY" ]; then
  rm -f "$BINARY"
  ok "Patched binary removed: $BINARY"
else
  ok "Patched binary not present."
fi

step "Removing versioned backups"
BACKUPS="$(ls -1 "$INSTALL_DIR/bin/" 2>/dev/null | grep -E '^opencode\.backup\.' || true)"
if [ -n "$BACKUPS" ]; then
  printf '%s\n' "$BACKUPS" | while read -r f; do
    rm -f "$INSTALL_DIR/bin/$f"
    printf '         removed: %s\n' "$(display_path "$INSTALL_DIR/bin/$f")"
  done
  ok "Backup binaries removed."
else
  ok "No backup binaries found."
fi

step "Removing install directory"
if [ "$REMOVE_USER_DATA" = "1" ]; then
  if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    ok "Install directory removed: $INSTALL_DIR"
  else
    ok "Install directory not present."
  fi
else
  if [ -d "$INSTALL_DIR" ]; then
    ok "Install directory preserved: $INSTALL_DIR (set REMOVE_USER_DATA=1 to remove)"
  else
    ok "Install directory not present."
  fi
fi

step "Checking command availability"
if command -v opencode >/dev/null 2>&1; then
  if [ "$FORCE" = "1" ]; then
    warn "opencode is still on PATH. Set FORCE=1 if you want to remove an unknown launcher."
  fi
  fail "opencode command is still available after uninstall."
fi
ok "opencode command is no longer available."

complete_banner
