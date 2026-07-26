# Upgrading Asimov

## To v0.10.0 (from the `django23/asimov` fork)

`0.10.0` folds the fork's work (v0.4.0–v0.8.0, plus a `v0.9.0-beta` round) back into
the original project, now homed at [`AsimovMac/asimov`](https://github.com/AsimovMac/asimov)
(transferred from `stevegrunwell/asimov`, which now redirects there). It also **reverts
the LaunchAgent label** from `com.django23.asimov` back to the original `com.stevegrunwell.asimov`.

The installers remove the old `com.django23.asimov` agent for you. If you want to
migrate by hand, unload the fork's agent first so you don't end up with two daily jobs:

```sh
launchctl bootout gui/$(id -u)/com.django23.asimov 2>/dev/null
rm ~/Library/LaunchAgents/com.django23.asimov.plist 2>/dev/null
```

Then install v0.10.0:

```sh
curl -fsSL https://raw.githubusercontent.com/AsimovMac/asimov/main/scripts/install-remote.sh | bash
```

Your `~/.config/asimov/config` and `~/.cache/asimov/` are unaffected.

# Upgrading to Asimov v0.5.0

## From v0.4.x (this fork)

v0.5.0 is a breaking release. Here's what changed:

### 1. Fixed directories are now opt-in

Global cache directories (`~/.cache`, `~/.gradle/caches`, etc.) are no longer excluded by default. To restore the previous behavior, create a config file:

```sh
mkdir -p ~/.config/asimov
cat > ~/.config/asimov/config << 'EOF'
[fixed_dirs]
enabled = true
EOF
```

### 2. LaunchAgent label changed

The plist label changed from `com.stevegrunwell.asimov` to `com.django23.asimov`. If upgrading a manual install, unload the old agent first:

```sh
launchctl unload ~/Library/LaunchAgents/com.stevegrunwell.asimov.plist 2>/dev/null
make install
```

Homebrew users: `brew upgrade` handles this automatically.

### 3. Output changes

- "Already excluded, skipping" messages are now hidden by default (use `--verbose` to see them).
- New `--quiet` flag suppresses all output except errors.
- ANSI colors are disabled when stdout is not a terminal (e.g. launchd logs).

## From stevegrunwell/asimov (original)

Welcome! This fork adds config file support, 30+ new ecosystem patterns, `--dry-run`, `--verbose`, `--quiet`, performance improvements, and daily scheduling via launchd.

### Step 1: Remove the original

```sh
brew uninstall asimov 2>/dev/null
# or, if installed manually:
launchctl unload ~/Library/LaunchAgents/com.stevegrunwell.asimov.plist 2>/dev/null
rm /usr/local/bin/asimov
```

### Step 2: Install this fork

```sh
curl -fsSL https://raw.githubusercontent.com/AsimovMac/asimov/v0.9.0-beta.1/scripts/install-remote.sh \
  | ASIMOV_REF=v0.9.0-beta.1 bash
```

### Step 3: (Optional) Enable global cache exclusions

The original asimov did not have this feature. To enable it:

```sh
mkdir -p ~/.config/asimov
cat > ~/.config/asimov/config << 'EOF'
[fixed_dirs]
enabled = true
EOF
```
