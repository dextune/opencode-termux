# Installation Details

This document describes the compatibility changes applied by `install-opencode-termux.sh` to make OpenCode run on Termux `aarch64`.

## Version status

- Completed target version: `1.17.18`
- npm umbrella package: `opencode-ai@1.17.18`
- npm platform binary: `opencode-linux-arm64@1.17.18`
- Runtime target: Android Termux `aarch64` with Termux glibc support

This installer is **frozen** at `1.17.18`. There is no `VERSION` override and no plan to publish a generic installer that picks a "latest" tag. Why is captured in the next section.

## Scope

The installer does not rebuild OpenCode and does not modify OpenCode source code. It installs the official npm packages from the public registry, copies the prebuilt platform binary, and then applies Termux-specific binary compatibility adjustments.

## 1. The `os.platform()` / `os.arch()` problem

OpenCode's npm umbrella package, `opencode-ai`, ships with a `postinstall.mjs` script that selects the correct platform package. The relevant code is:

```js
const platformMap = { darwin: "darwin", linux: "linux", win32: "windows" }
const archMap = { x64: "x64", arm64: "arm64", arm: "arm" }

const platform = platformMap[os.platform()] ?? os.platform()
const arch = archMap[os.arch()] ?? os.arch()
const base = `opencode-${platform}-${arch}`
```

On Termux:

- `os.platform()` returns `android`
- `os.arch()` returns `arm64`

The lookup table has no key for `android`, so `platformMap[os.platform()]` is `undefined` and the fallback `os.platform()` produces `android`. The composed base is therefore `opencode-android-arm64`, which is **not published to the npm registry**. The official `postinstall` then aborts with:

```text
It seems your package manager failed to install the right opencode CLI package.
Try manually installing "opencode-android-arm64".
```

This happens regardless of whether you install `opencode-ai` with `--force` (which only bypasses npm's own `EBADPLATFORM` check), because the postinstall runs against the *resolved* package list and still tries to load the Android binary.

The installer avoids this entirely by passing `--ignore-scripts` to `npm install`, then performing the platform binary copy and ELF patch itself.

## 2. ELF interpreter patch

The prebuilt binary at `node_modules/opencode-linux-arm64/bin/opencode` is an ELF aarch64 executable with the standard Linux dynamic loader as its interpreter:

```text
/lib/ld-linux-aarch64.so.1
```

Termux does not provide that path. The installer uses `patchelf-glibc` through `glibc-runner` to point the binary at the Termux glibc loader:

```text
/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1
```

Command shape:

```sh
glibc-runner patchelf --set-interpreter \
  /data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1 \
  /data/data/com.termux/files/home/.local/share/opencode/bin/opencode
```

This changes ELF metadata. It does not rewrite application logic.

## 3. Launcher wrapper

The installer writes a launcher to:

```text
/data/data/com.termux/files/usr/bin/opencode
```

The wrapper clears library-path variables that can interfere with a glibc binary and then execs the patched binary:

```sh
#!/data/data/com.termux/files/usr/bin/sh
unset LD_PRELOAD
unset LD_LIBRARY_PATH
exec /data/data/com.termux/files/home/.local/share/opencode/bin/opencode "$@"
```

Because the patched binary already has the Termux glibc loader as its ELF interpreter, the wrapper execs it directly — no `glibc-runner` wrapper is needed at runtime.

## 4. Why `--ignore-scripts`

`opencode-ai`'s postinstall does three things if allowed to run:

1. Probe the running Node binary for `process.platform` / `process.arch`.
2. Resolve a package named `opencode-${platform}-${arch}`.
3. Copy that package's `bin/opencode` into `node_modules/opencode-ai/bin/opencode.exe`.

Step 2 always produces `opencode-android-arm64` on Termux, which does not exist. So `postinstall` exits non-zero and (depending on npm version) may even leave `bin/opencode.exe` as the placeholder error script that says `Error: opencode-ai's postinstall script was not run.`

The installer runs the npm install with `--ignore-scripts`, then performs the copy itself: it copies `node_modules/opencode-linux-arm64/bin/opencode` directly into `~/.local/share/opencode/bin/opencode`. This bypasses both the missing Android package and the placeholder-error side effect.

## 5. Verification points

The installer verifies:

- Node.js >= 18 is available
- `glibc-runner` and `patchelf-glibc` are installed
- `opencode-ai@1.17.18` and `opencode-linux-arm64@1.17.18` are installed in the global npm prefix
- the platform package's binary exists and is executable
- `patchelf --print-interpreter` reports the Termux glibc loader path
- `opencode --version` reports `1.17.18`

Manual checks:

```sh
command -v opencode
opencode --version
glibc-runner /data/data/com.termux/files/usr/glibc/bin/patchelf \
  --print-interpreter ~/.local/share/opencode/bin/opencode
opencode run "say hi in one short sentence"
```

Expected output (final line is the OpenCode response, which depends on the configured provider/model):

```text
/data/data/com.termux/files/usr/bin/opencode
1.17.18
/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1
Hi.
```

## 6. Upstream change risks

Future OpenCode versions may require changes if upstream changes:

- npm package layout (new optional dependencies, new platform keys)
- the `postinstall.mjs` resolution logic
- ELF interpreter path or other ELF fields
- glibc version requirements
- the placement or naming of the prebuilt binary inside the platform package

The `--ignore-scripts` + manual copy pattern is the load-bearing trick: as long as the prebuilt binary lives at `node_modules/opencode-linux-arm64/bin/opencode` and is a glibc ELF aarch64 executable, the installer continues to work.

## 7. Version freeze policy

Because every byte-level patch in this repository (the ELF interpreter path string, the `glibc-loader` runtime location, the file-descriptor wiring inside the launcher, etc.) was validated against a specific build of the binary, this installer is intentionally frozen at a single release:

- `opencode-ai@1.17.18`
- `opencode-linux-arm64@1.17.18`

The script does not expose a `VERSION` knob. If a future OpenCode release changes any of the points listed in section 6, this installer will either silently fail or, worse, appear to succeed while producing a binary that does not actually run. Neither outcome is acceptable, so the policy is:

1. The installer hard-codes the supported version as `FROZEN_VERSION` and aborts if `VERSION` is set to anything else.
2. The README's "Change version" section describes the manual steps required to re-validate and re-publish the installer for a new release.
3. Until those steps are completed for a new upstream version, the right way to install OpenCode on Termux is to stay on `1.17.18`.

This is the same trade-off the Termux glibc binary itself makes: the loader at `/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1` does not change shape every time a new package is published. Pin the dependencies, audit the boundaries, then commit to the result.