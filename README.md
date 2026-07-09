# OpenCode for Termux

<p align="center">
  <img src="assets/banner.png" alt="OpenCode for Termux banner" width="768">
</p>

This script is for Android Termux only. It installs [OpenCode](https://github.com/sst/opencode) from the official npm registry and applies the compatibility patches required to run it on Termux `aarch64`.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/dextune/opencode-termux/main/install-opencode-termux.sh | sh
```

Or, if you already cloned this repository:

```sh
sh ./install-opencode-termux.sh
```

```text
OpenCode for Termux
Compatibility installer for Android/aarch64

Target version : 1.17.15
Platform       : opencode-linux-arm64
Install path   : .../share/opencode/bin/opencode
Launcher       : .../usr/bin/opencode
```

## Version status

This installer is **frozen for a single OpenCode release**. It only supports:

- OpenCode version: `1.17.15`
- npm umbrella package: `opencode-ai@1.17.15`
- npm platform binary: `opencode-linux-arm64@1.17.15`

The `VERSION` environment variable is intentionally ignored. Setting `VERSION` to anything other than `1.17.15` makes the installer abort. There is no "Change version" option on purpose.

### Why a freeze

OpenCode's ELF patches (interpreter path, file-descriptor wiring, copy target layout) only apply to the exact build of `opencode-linux-arm64@1.17.15` that this repository was validated against. Newer or older builds can have:

- a different `postinstall.mjs` that no longer selects `opencode-linux-arm64` from inside `opencode-ai`;
- a different ELF layout (interpreter path, section alignment, dynamic tags);
- a different glibc requirement;
- a different placement or naming of the prebuilt binary inside the platform package.

When upstream releases a new version, every patch in this repository has to be re-validated against the new build before this installer can be updated. Until then, the right way to install OpenCode on Termux is to use the build this repository was tested with — `1.17.15` — and to wait for an updated installer before upgrading.

## What this installer does

OpenCode is published on npm. The umbrella package is `opencode-ai`, and each supported platform has its own optional dependency package (`opencode-linux-arm64`, `opencode-darwin-x64`, etc.). The umbrella package's `postinstall` script picks the correct platform package by calling `os.platform()` and `os.arch()` from Node and resolving a package named `opencode-${platform}-${arch}`.

On Termux, `os.platform()` reports `android` rather than `linux`. There is no `opencode-android-arm64` package, so the official `postinstall` aborts with `Try manually installing "opencode-android-arm64"`. Even if you bypass that with `npm install --force`, the official `postinstall` still tries to resolve the Android package and fails.

This Termux installer works around that by:

1. Installing required Termux packages.
2. Removing any previous opencode installation (launcher, ELF binary, npm packages).
3. Installing `opencode-ai@1.17.15` with `--force --ignore-scripts --os=linux --cpu=arm64`. `--force` bypasses npm's `EBADPLATFORM` check, and `--ignore-scripts` skips the upstream postinstall that looks for `opencode-android-arm64`.
4. Installing `opencode-linux-arm64@1.17.15` with the same flags. This package contains the actual prebuilt ELF binary.
5. Copying the ELF binary from the platform package into `~/.local/share/opencode/bin/opencode`.
6. Using `glibc-runner patchelf` to rewrite the ELF interpreter from `/lib/ld-linux-aarch64.so.1` to Termux's glibc loader at `/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1`.
7. Installing an `opencode` launcher at `/data/data/com.termux/files/usr/bin/opencode` that clears `LD_PRELOAD` / `LD_LIBRARY_PATH` and execs the patched binary.
8. Running `opencode --version` and confirming that it reports `1.17.15`.

## Requirements

- Android with Termux.
- `aarch64` or `arm64` CPU architecture.
- Node.js 18 or newer (the installer installs `nodejs` from the Termux package repository if it is not already present).
- Network access to the npm registry.
- Enough storage for Termux packages, the OpenCode npm package, the platform binary (~175 MB), and the patched binary.

The script installs its own package dependencies through `pkg`, including `curl`, `jq`, `nodejs`, `glibc-runner`, and `patchelf-glibc`.

## Installer output

The installer displays an OpenCode-style terminal screen and numbered progress steps:

```text
OpenCode for Termux
Compatibility installer for Android/aarch64

Target version : 1.17.15
Platform       : opencode-linux-arm64
Install path   : .../share/opencode/bin/opencode
Launcher       : .../usr/bin/opencode

[01/10] Installing required Termux packages
         done: Required Termux packages are installed.

[10/10] Verifying patched installation
1.17.15
         done: OpenCode 1.17.15 is installed successfully.

Installation complete

OpenCode 1.17.15 has been installed.
Command: opencode
Path   : .../usr/bin/opencode
```

## Installed files

Default paths:

- Launcher: `/data/data/com.termux/files/usr/bin/opencode`
- Patched binary: `~/.local/share/opencode/bin/opencode`
- npm packages: `node_modules/opencode-ai` and `node_modules/opencode-linux-arm64` (under your global npm prefix)

If an existing launcher or binary is found, the installer creates a timestamped backup before replacing it.

## Verify installation

Run:

```sh
command -v opencode
opencode --version
```

Expected output:

```text
/data/data/com.termux/files/usr/bin/opencode
1.17.15
```

You can also confirm the patched ELF interpreter:

```sh
glibc-runner /data/data/com.termux/files/usr/glibc/bin/patchelf \
  --print-interpreter ~/.local/share/opencode/bin/opencode
```

Expected output:

```text
/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1
```

To send a one-shot prompt:

```sh
opencode run "say hi in one short sentence"
```

## Uninstall

Use the one-shot uninstaller below in Termux:

```sh
curl -fsSL https://raw.githubusercontent.com/dextune/opencode-termux/main/uninstall-opencode-termux.sh | sh
```

Or, if you already cloned this repository:

```sh
sh ./uninstall-opencode-termux.sh
```

By default, uninstall removes:

- `/data/data/com.termux/files/usr/bin/opencode`
- `~/.local/share/opencode/bin/opencode`
- the global npm packages `opencode-ai` and `opencode-linux-arm64`
- timestamped backups for this version

By default, uninstall preserves:

- `~/.local/share/opencode` (logs, sessions, repo caches)

## Remove user data

To remove OpenCode user data as well:

```sh
curl -fsSL https://raw.githubusercontent.com/dextune/opencode-termux/main/uninstall-opencode-termux.sh | REMOVE_USER_DATA=1 sh
```

If you already cloned this repository:

```sh
REMOVE_USER_DATA=1 sh ./uninstall-opencode-termux.sh
```

## Change version

This installer does not support changing versions. The `VERSION` environment variable is intentionally ignored. To install a different OpenCode release, you must:

1. Verify the new upstream release manually against this repository's patch points.
2. Update the `FROZEN_VERSION` constant at the top of `install-opencode-termux.sh` and `uninstall-opencode-termux.sh`.
3. Update the `VERSION` line in the banner output and the version status section in `README.md` / `README_ko.md`.
4. Re-run the installer on a clean environment and confirm the same checks documented in `INSTALLATION_DETAILS.md` still pass.

Until that work is done, stick with `1.17.15`.

## Patch details

This project does not rebuild OpenCode and does not modify OpenCode source code. It downloads the official npm packages, copies the prebuilt platform binary, and applies the minimal runtime compatibility changes needed for Termux.

See `INSTALLATION_DETAILS.md` for the technical installation and patch details.