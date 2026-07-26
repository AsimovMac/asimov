# asimov

**Stop backing up files you'll never restore.**

[![Tests](https://github.com/AsimovMac/asimov/actions/workflows/tests.yml/badge.svg)](https://github.com/AsimovMac/asimov/actions/workflows/tests.yml)
[![Latest release](https://img.shields.io/github/v/release/AsimovMac/asimov?include_prereleases&sort=semver&color=blue)](https://github.com/AsimovMac/asimov/releases)
[![Stars](https://img.shields.io/github/stars/AsimovMac/asimov?style=flat)](https://github.com/AsimovMac/asimov/stargazers)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white)](https://support.apple.com/en-us/HT201250)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE.txt)
[![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](asimov)

Every Time Machine snapshot copies your `node_modules`, `.venv`, `target`, `DerivedData`; gigabytes of files you can rebuild with one command. With git worktrees and AI coding agents spinning up parallel copies of every project, that waste compounds fast.

Asimov scans your home directory, finds dependency folders next to their config files, and tells Time Machine to skip them. Install once, run daily, forget it exists.

## Install

### Homebrew

```sh
brew install asimov
brew services start asimov
```

> **Updating to v0.10.0:** the homebrew-core formula is being bumped from `0.3.0` → `0.10.0` ([tracking PR](https://github.com/Homebrew/homebrew-core/pulls?q=asimov)). Until it merges, `brew install asimov` still installs `0.3.0` — use the curl installer below for `0.10.0` today.

### curl (latest, no Homebrew)

```sh
curl -fsSL https://raw.githubusercontent.com/AsimovMac/asimov/main/scripts/install-remote.sh | bash
```

Installs `v0.10.0` to `~/.local/bin`. Found a bug? [Open an issue](https://github.com/AsimovMac/asimov/issues).

### Quick start

```sh
asimov --dry-run    # preview what would be excluded — changes nothing
asimov              # apply
```

That's it. Asimov then runs itself once a day, every day. Add `--stats` to either command to see sizes and how much space you're saving.

See [other install methods](#other-install-methods) to build from source.

## What you'll see

```
$ asimov --dry-run --stats

⏳ Scanning for dependency directories…
📦 Processing matches…
- Would exclude: ~/Code/myapp/node_modules (412M).
- Would exclude: ~/Code/myapp/.next (89M).
- Would exclude: ~/Code/api/.venv (1.2G).
- Would exclude: ~/Code/rust-cli/target (2.4G).
- Would exclude: ~/Code/worktrees/feature-auth/node_modules (1.6G).
- Would exclude: ~/Code/worktrees/feature-auth/.next (492M).
- Would exclude: ~/Code/worktrees/refactor-billing/node_modules (1.6G).
…

Would exclude 27 directories, totalling 18.4G.
```

`--dry-run` previews without changing anything. Drop the flag — and the `--stats` if you want it fast — to apply.

## How it works

Asimov pairs each dependency directory with a **sentinel** config file. A folder is only excluded if its sentinel exists alongside it:

- `node_modules/` → requires `package.json`
- `vendor/` → requires `composer.json` or `go.mod`
- `target/` → requires `Cargo.toml` or `pom.xml`

This means Asimov never touches a folder that just happens to share a common name. Safe to run anywhere in your home directory.

**Supported ecosystems (30+ patterns)**


| Ecosystem                   | Directories excluded                                                                                                             |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| **JavaScript / TypeScript** | `node_modules`, `.next`, `.nuxt`, `.angular`, `.svelte-kit`, `.turbo`, `.yarn`, `.parcel-cache`, `bower_components`, `elm-stuff` |
| **Monorepo**                | `.moon/cache`                                                                                                                    |
| **Python**                  | `.venv`, `venv`, `.tox`, `.nox`, `__pypackages__`, `build`, `dist`                                                               |
| **Rust**                    | `target`                                                                                                                         |
| **Go**                      | `vendor`                                                                                                                         |
| **PHP**                     | `vendor`                                                                                                                         |
| **Ruby**                    | `vendor`                                                                                                                         |
| **Java / Kotlin / Scala**   | `.gradle`, `build`, `target`                                                                                                     |
| **.NET (C# / F#)**          | `bin`, `obj`                                                                                                                     |
| **Swift / Apple**           | `.build`, `Carthage`, `Pods`, `DerivedData`                                                                                      |
| **Dart / Flutter**          | `.dart_tool`, `.packages`, `build`                                                                                               |
| **Elixir**                  | `deps`, `_build`, `.build`                                                                                                       |
| **Clojure**                 | `target`, `.cpcache`, `.shadow-cljs`                                                                                             |
| **Haskell**                 | `.stack-work`                                                                                                                    |
| **OCaml**                   | `_build`                                                                                                                         |
| **Zig**                     | `.zig-cache`, `zig-out`                                                                                                          |
| **R**                       | `renv`                                                                                                                           |
| **DevOps / IaC**            | `.terraform`, `.terragrunt-cache`, `.vagrant`, `.direnv`, `cdk.out`                                                              |
| **Game dev**                | `.godot`                                                                                                                         |
| **Global caches** (opt-in)  | `~/.cache`, `~/.gradle/caches`, `~/.m2/repository`, `~/.npm/_cacache`, `~/.nuget/packages`, `~/.kube/cache`, `~/go/pkg/mod`         |

**Don't see your tool?** You can teach Asimov your own directory + sentinel pairs in a couple of lines — no need to wait for a release. See [Add your own patterns](#add-your-own-patterns).


## Usage

```
asimov [--dry-run] [--verbose] [--quiet] [--stats] [--no-read-cache] [--no-write-cache] [--help] [--version] [directory]
```


| Option              | Description                                                       |
| ------------------- | ---------------------------------------------------------------- |
| `--dry-run`         | Print what would be excluded without changing Time Machine       |
| `--verbose`         | Show all directories including already-excluded ones             |
| `--quiet`           | Suppress all output except errors                                |
| `--stats`           | Show per-directory sizes and a total-space summary               |
| `--no-read-cache`   | Ignore cached state; re-discover and re-verify everything, then rebuild the cache |
| `--no-write-cache`  | Run normally but don't persist any cache updates                 |

Asimov keeps a cache under `~/.cache/asimov/` so repeat runs are near-instant. The two flags above control it on independent axes — reading and writing:

- `--no-read-cache` — *"rebuild."* Ignores everything cached, re-scans the filesystem, and re-verifies every directory against Time Machine, then writes a fresh cache. **`--full-scan` is an alias.**
- `--no-write-cache` — *"don't touch state."* Uses the fast cache to read, but persists nothing. Handy with `--dry-run`.
- Both together = a fully stateless run that reads and writes nothing. **`--no-cache` is an alias for this.**


## Schedule

The curl and source installers set up a daily launchd job automatically. To trigger one immediately or stop the schedule:

```sh
launchctl kickstart gui/$(id -u)/com.stevegrunwell.asimov   # run now
launchctl bootout   gui/$(id -u)/com.stevegrunwell.asimov   # stop schedule
```

## Configuration

Asimov works out of the box. To customize it, drop a config file at `~/.config/asimov/config`. The most useful thing you can do here is **teach it dependency directories of your own.**

### Scan more than your home directory

By default Asimov scans your home directory. Keep projects elsewhere too — say under `/private/var/www`? Add each extra root under a `[scan]` section and it's scanned on every run, alongside home:

```ini
[scan]
extra = /private/var/www         # one "extra =" line per directory
extra = /Volumes/Work/clients    # ~ is expanded, e.g. extra = ~/Sites
```

Your home directory is always scanned; these are added to it. Configured directories that don't exist (an unmounted volume, say) are skipped with a warning instead of failing the run. Passing a directory on the command line (`asimov /some/path`) still overrides everything and scans only that path.

### Add your own patterns

Using a tool Asimov doesn't know about yet? Add it yourself. Each pattern is a `directory sentinel` pair — exactly the same mechanism the [built-ins](#how-it-works) use: the directory is excluded **only** when the sentinel file sits right beside it, so it's safe even for common folder names.

```ini
[sentinels]
extra = .cache my-tool.toml      # exclude .cache only when my-tool.toml is its sibling
extra = generated codegen.yml    # one "extra =" line per pattern
extra = dist *.podspec           # glob sentinels work too
```

Want to turn a built-in off? List its exact pair under `disabled`:

```ini
[sentinels]
disabled = vendor Gemfile        # stop excluding Ruby's vendor/ directories
```

### Global caches (opt-in)

Global tool caches in your home directory (`~/.cache`, `~/.gradle/caches`, …) are left alone by default. Opt in, and add paths of your own:

```ini
[fixed_dirs]
enabled = true                   # exclude the built-in global caches
extra   = ~/my-build-cache       # plus any paths you name (always excluded when they exist)
extra   = ~/golang/pkg/mod       # e.g. a Go module cache under a custom GOPATH
```

### Exclude paths from search
Sometimes you may want to exclude directories from the search. By default, Asimov excludes `~/.Trash`
and `~/Library` to avoid modifying Time Machine exclusions for these paths. You can add additional paths to the search exclusion list:

```ini
[skip_paths]
extra = ~/Music
extra = ~/Pictures
```

`skip_paths` does not exclude global caches defined in `fixed_dirs`.

If your code is contained to a single subfolder, you may want to only search that subfolder instead by specifying the directory argument in the CLI ([see usage](#usage)).

## Other install methods

**From source:**

```sh
git clone https://github.com/AsimovMac/asimov.git --depth 1
cd asimov && make install
```

## Uninstall

```sh
rm ~/.local/bin/asimov                                    # curl install
brew uninstall asimov                                     # Homebrew
launchctl bootout gui/$(id -u)/com.stevegrunwell.asimov   # stop schedule
make uninstall                                            # source install
```

## Upgrading

See [UPGRADING.md](UPGRADING.md) for migrating from v0.4.x or the original `stevegrunwell/asimov`.

## Credits

Asimov was created by **[Steve Grunwell](https://github.com/stevegrunwell)**, who built and maintained it at `stevegrunwell/asimov` from 2018 through v0.3.0 — the version most people know it by. Thank you, Steve, for the years of work and for [handing it on](https://github.com/AsimovMac/asimov/issues/99) so carefully.

The project now lives at [`AsimovMac/asimov`](https://github.com/AsimovMac/asimov) (the original repo, transferred — the old URL still redirects here), maintained by [@django23](https://github.com/django23). Releases from `v0.4.0` onward add expanded ecosystem coverage, a config file, and the caching that took typical runs from ~75s to ~1–2s.

Built on the contributions of everyone who filed issues and PRs over the years. Asimov is, and stays, MIT-licensed and community-driven.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and guidelines. Security issues: see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE.txt)
