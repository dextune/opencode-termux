#!/data/data/com.termux/files/usr/bin/sh
set -eu

# OpenCode Termux installer.
#
# OpenCode is published on npm as `opencode-ai`, with platform-specific
# binaries in separate optional packages (`opencode-linux-arm64`, etc.).
# The npm postinstall script selects the correct platform package by
# running `os.platform()` / `os.arch()` in Node and resolving a package
# named `opencode-${platform}-${arch}`. On Termux, `os.platform()` reports
# `android`, so the postinstall looks for the non-existent
# `opencode-android-arm64` package and aborts.
#
# This installer works around that by:
#   1. Installing `opencode-ai` and `opencode-linux-arm64` with
#      `--force --ignore-scripts --os=linux --cpu=arm64` (the platform
#      check is bypassed and the upstream postinstall is skipped).
#   2. Copying the prebuilt ELF binary from `opencode-linux-arm64` into
#      `~/.local/share/opencode/bin/opencode`.
#   3. Rewriting the ELF interpreter with `glibc-runner patchelf` to point
#      at Termux's glibc loader (the default `/lib/ld-linux-aarch64.so.1`
#      does not exist on Termux).
#   4. Dropping a small launcher at `$PREFIX/bin/opencode` that clears
#      `LD_PRELOAD` / `LD_LIBRARY_PATH` and execs the patched binary.
#
# VERSION FREEZE
#   This installer is frozen for opencode-ai 1.17.18. The binary patches
#   (ELF interpreter path, file descriptor wiring, etc.) only apply to
#   the exact build of `opencode-linux-arm64@1.17.18`. Newer or older
#   versions can have a different ELF layout, glibc requirements, or
#   `postinstall.mjs` resolution logic that this script does not handle.
#   When upgrading to a new upstream release, re-validate every patch on
#   the new binary before publishing a new installer. The actual freeze
#   check lives below, right after `fail()` is defined.

FROZEN_VERSION="1.17.18"
PLATFORM_PKG="opencode-linux-arm64"

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.local/share/opencode/bin}"
BINARY="$INSTALL_DIR/opencode"
WRAPPER="$PREFIX/bin/opencode"

GLIBC_RUNNER="$PREFIX/bin/glibc-runner"
PATCHELF_GLIBC="$PREFIX/glibc/bin/patchelf"
GLIBC_LOADER="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"

NPM_PREFIX="$(npm root -g)"
NPM_AI_DIR="$NPM_PREFIX/opencode-ai"
NPM_PLATFORM_DIR="$NPM_PREFIX/opencode-${PLATFORM_PKG#opencode-}"
NPM_PLATFORM_BIN="$NPM_PLATFORM_DIR/bin/opencode"

STEP_INDEX=0
STEP_TOTAL=10

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
| Compatibility installer for Android/aarch64               |
+------------------------------------------------------------+
EOF
  printf '| %-58s |\n' "Target version : $VERSION"
  printf '| %-58s |\n' "Platform       : $PLATFORM_PKG"
  printf '| %-58s |\n' "Install path   : $(display_path "$BINARY")"
  printf '| %-58s |\n' "Launcher       : $(display_path "$WRAPPER")"
  cat <<EOF
+------------------------------------------------------------+

EOF
}

step() {
  STEP_INDEX=$((STEP_INDEX + 1))
  printf '\n[%02d/%02d] %s\n' "$STEP_INDEX" "$STEP_TOTAL" "$*"
}

ok() {
  printf '         done: %s\n' "$*"
}

warn() {
  printf '%s\n' "Warning: $*" >&2
}

fail() {
  printf '%s\n' "Error: $*" >&2
  exit 1
}

if [ -n "${VERSION:-}" ] && [ "$VERSION" != "$FROZEN_VERSION" ]; then
  fail "This installer is frozen for opencode-ai $FROZEN_VERSION. The VERSION env var is set to '$VERSION', but the supported value is '$FROZEN_VERSION'. When upstream releases a new version, re-validate every patch on the new binary before publishing a new installer."
fi
VERSION="$FROZEN_VERSION"

complete_banner() {
  cat <<EOF

+------------------------------------------------------------+
| Installation complete                                      |
+------------------------------------------------------------+
EOF
  printf '| %-58s |\n' "OpenCode $VERSION has been installed."
  printf '| %-58s |\n' "Command: opencode"
  printf '| %-58s |\n' "Path   : $(display_path "$WRAPPER")"
  cat <<EOF
+------------------------------------------------------------+

EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is not available: $1"
}

backup_if_exists() {
  target_path="$1"
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    timestamp="$(date +%Y%m%d%H%M%S)"
    backup_path="$target_path.backup.$timestamp"
    mv "$target_path" "$backup_path"
    ok "Existing file was backed up: $backup_path"
  fi
}

# ---- preflight --------------------------------------------------------------

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) fail "Unsupported architecture: $(uname -m). This installer supports Termux aarch64/arm64 only." ;;
esac

case "$PREFIX" in
  */com.termux/files/usr) ;;
  *) warn "PREFIX is set to $PREFIX. This installer is intended for Termux." ;;
esac

WORK_DIR="$(mktemp -d "$PREFIX/tmp/opencode-install-$VERSION.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

banner

step "Installing required Termux packages"
export DEBIAN_FRONTEND=noninteractive
pkg update -y
pkg install -y ca-certificates curl jq gnupg nodejs file coreutils grep sed gawk perl glibc-repo
pkg update -y
pkg install -y glibc-runner patchelf-glibc
ok "Required Termux packages are installed."

require_command curl
require_command jq
require_command node
require_command npm
require_command sed
require_command grep

[ -x "$GLIBC_RUNNER" ] || fail "glibc-runner was not found at $GLIBC_RUNNER"
[ -x "$PATCHELF_GLIBC" ] || fail "patchelf-glibc was not found at $PATCHELF_GLIBC"
[ -e "$GLIBC_LOADER" ] || fail "glibc loader was not found at $GLIBC_LOADER"

NODE_MAJOR="$(node -v | sed -n 's/^v\([0-9]*\).*/\1/p')"
[ "${NODE_MAJOR:-0}" -ge 18 ] || fail "Node.js >= 18 is required (found: $(node -v))."

step "Removing previous opencode installation"
if command -v opencode >/dev/null 2>&1; then
  rm -f "$WRAPPER"
  ok "Existing launcher removed."
fi
if [ -d "$NPM_AI_DIR" ]; then
  npm uninstall -g opencode-ai >/dev/null 2>&1 || true
  ok "Previous opencode-ai npm package removed."
fi
if [ -d "$NPM_PLATFORM_DIR" ]; then
  npm uninstall -g "$PLATFORM_PKG" >/dev/null 2>&1 || true
  ok "Previous $PLATFORM_PKG npm package removed."
fi
if [ -e "$BINARY" ]; then
  rm -f "$BINARY"
  ok "Existing patched binary removed."
fi

# ---- npm install (bypass postinstall + EBADPLATFORM) ------------------------

step "Installing opencode-ai@$VERSION (postinstall skipped)"
# Termux reports os=android, but the platform binary targets linux-arm64.
# --force bypasses npm's EBADPLATFORM check.
# --ignore-scripts bypasses opencode-ai's postinstall which would try to
# resolve `opencode-android-arm64` (a package that does not exist).
npm install -g --force --ignore-scripts --os=linux --cpu=arm64 "opencode-ai@$VERSION" >/dev/null 2>&1 || \
  fail "Failed to install opencode-ai@$VERSION. Check npm logs."
[ -d "$NPM_AI_DIR" ] || fail "opencode-ai was not installed at $NPM_AI_DIR"
ok "opencode-ai@$VERSION installed at $(display_path "$NPM_AI_DIR")"

step "Installing $PLATFORM_PKG@$VERSION (postinstall skipped)"
npm install -g --force --ignore-scripts --os=linux --cpu=arm64 "$PLATFORM_PKG@$VERSION" >/dev/null 2>&1 || \
  fail "Failed to install $PLATFORM_PKG@$VERSION. Check npm logs."
[ -x "$NPM_PLATFORM_BIN" ] || fail "Platform binary was not installed at $NPM_PLATFORM_BIN"
ok "$PLATFORM_PKG@$VERSION installed at $(display_path "$NPM_PLATFORM_DIR")"

# ---- binary copy + ELF patch -------------------------------------------------

mkdir -p "$INSTALL_DIR"

step "Copying patched ELF binary into place"
cp "$NPM_PLATFORM_BIN" "$BINARY"
chmod 755 "$BINARY"
ok "Binary copied: $BINARY"

step "Patching ELF interpreter for Termux glibc"
# The upstream binary expects /lib/ld-linux-aarch64.so.1, which does not
# exist on Termux. Use glibc-runner + patchelf to point it at the Termux
# glibc loader so the launcher can exec it directly.
glibc-runner "$PATCHELF_GLIBC" --set-interpreter "$GLIBC_LOADER" "$BINARY"
ok "ELF interpreter patched -> $GLIBC_LOADER"

step "Installing opencode launcher"
backup_if_exists "$WRAPPER"
cat > "$WRAPPER" <<EOF
#!$PREFIX/bin/sh
unset LD_PRELOAD
unset LD_LIBRARY_PATH
exec "$BINARY" "\$@"
EOF
chmod 755 "$WRAPPER"
ok "Launcher installed: $WRAPPER"

# ---- verification ------------------------------------------------------------

step "Verifying patched installation"
INTERPRETER="$(glibc-runner "$PATCHELF_GLIBC" --print-interpreter "$BINARY")"
[ "$INTERPRETER" = "$GLIBC_LOADER" ] || fail "Unexpected ELF interpreter: $INTERPRETER"

VERSION_OUTPUT="$(opencode --version 2>&1)"
printf '%s\n' "$VERSION_OUTPUT"
printf '%s\n' "$VERSION_OUTPUT" | grep -q "$VERSION" || fail "opencode --version did not report $VERSION."

ok "OpenCode $VERSION is installed successfully."
complete_banner