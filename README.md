# asimov

Exclude development dependencies from Time Machine backups. Automatically.

[![Tests](https://github.com/django23/asimov/actions/workflows/tests.yml/badge.svg)](https://github.com/django23/asimov/actions/workflows/tests.yml)
[![Latest release](https://img.shields.io/github/v/release/django23/asimov?sort=semver&color=blue)](https://github.com/django23/asimov/releases)
[![Stars](https://img.shields.io/github/stars/django23/asimov?style=flat)](https://github.com/django23/asimov/stargazers)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white)](https://support.apple.com/en-us/HT201250)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE.txt)
[![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](asimov)

Asimov scans your home directory for known dependency directories (`node_modules/`, `vendor/`, `.venv/`, etc.), verifies the corresponding config file exists, and **tells Time Machine to skip them**. No more wasting backup space on files you can restore with a single command.

## Install

**Homebrew:**

```sh
brew install django23/tap/asimov
```

**Or with curl (no Homebrew required):**

```sh
curl -fsSL https://raw.githubusercontent.com/django23/asimov/main/scripts/install-remote.sh | bash
```

**Or manually:**

```sh
git clone https://github.com/django23/asimov.git --depth 1
cd asimov
make install
```

## Usage

```
asimov [--dry-run] [--verbose] [--quiet] [--help] [--version]
```

| Option | Description |
|---|---|
| `--dry-run` | Print what would be excluded without changing Time Machine |
| `--verbose` | Show all directories including already-excluded ones |
| `--quiet` | Suppress all output except errors |

Or run on demand: `asimov`

## Schedule

Set up a daily launchd job so asimov runs automatically at midday:

```sh
# Homebrew users:
brew services start django23/tap/asimov

# Manual/curl installs (already set up by the installer):
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.django23.asimov.plist
```

To trigger a run immediately:

```sh
launchctl kickstart gui/$(id -u)/com.django23.asimov
```

To stop the scheduled job:

```sh
launchctl bootout gui/$(id -u)/com.django23.asimov
```

## What it does

Asimov pairs each dependency directory with a "sentinel" config file. A directory is only excluded if its sentinel exists — `node_modules` requires `package.json`, `vendor` requires `composer.json` or `go.mod`, and so on. This prevents false positives on directories that happen to share a common name.

Optionally, asimov can also exclude well-known global caches (`~/.cache`, `~/.gradle/caches`, etc.) when enabled via the config file.

<details>
<summary><strong>Supported ecosystems (30+ patterns)</strong></summary>

| Ecosystem | Directories excluded |
|---|---|
| **JavaScript / TypeScript** | `node_modules`, `.next`, `.nuxt`, `.angular`, `.svelte-kit`, `.turbo`, `.yarn`, `.parcel-cache`, `bower_components`, `elm-stuff` |
| **Python** | `.venv`, `venv`, `.tox`, `.nox`, `__pypackages__`, `build`, `dist` |
| **Rust** | `target` |
| **Go** | `vendor` |
| **PHP** | `vendor` |
| **Ruby** | `vendor` |
| **Java / Kotlin / Scala** | `.gradle`, `build`, `target` |
| **.NET (C# / F#)** | `bin`, `obj` |
| **Swift / Apple** | `.build`, `Carthage`, `Pods`, `DerivedData` |
| **Dart / Flutter** | `.dart_tool`, `.packages`, `build` |
| **Elixir** | `deps`, `_build`, `.build` |
| **Clojure** | `target`, `.cpcache`, `.shadow-cljs` |
| **Haskell** | `.stack-work` |
| **OCaml** | `_build` |
| **Zig** | `.zig-cache`, `zig-out` |
| **R** | `renv` |
| **DevOps / IaC** | `.terraform`, `.terragrunt-cache`, `.vagrant`, `.direnv`, `cdk.out` |
| **Game dev** | `.godot` |
| **Global caches** (opt-in) | `~/.cache`, `~/.gradle/caches`, `~/.m2/repository`, `~/.npm/_cacache`, `~/.nuget/packages`, `~/.kube/cache` |

</details>

## Configuration

Asimov reads an optional config file at `~/.config/asimov/config`:

```ini
[fixed_dirs]
# Enable global cache exclusions (default: false)
enabled = true

# Add your own always-exclude paths
extra = ~/my-build-cache

[sentinels]
# Add custom dependency patterns
extra = .custom-deps custom.config

# Disable a built-in pattern
disabled = vendor Gemfile
```

No config file needed for the default sentinel-based behavior.

## Upgrading

See [UPGRADING.md](UPGRADING.md) for migration instructions from v0.4.x or from the [original asimov](https://github.com/stevegrunwell/asimov).

## Uninstall

```sh
brew uninstall asimov                    # Homebrew
# or
rm ~/.local/bin/asimov                   # curl install
launchctl bootout gui/$(id -u)/com.django23.asimov
# or
make uninstall                           # manual install
```

## Credits

Asimov was originally created by [Steve Grunwell](https://github.com/stevegrunwell/asimov). This fork is actively maintained at [django23/asimov](https://github.com/django23/asimov) with performance improvements, config file support, and expanded ecosystem coverage.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and guidelines.

## License

[MIT](LICENSE.txt)
