# Asimov Change Log

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

### Added

### Changed

### Fixed

### Removed

## [0.9.0] — 2026-07-09

First release under the project's new home, [`AsimovMac/asimov`](https://github.com/AsimovMac/asimov)
— the original [`stevegrunwell/asimov`](https://github.com/stevegrunwell/asimov)
repository transferred to a dedicated organization (stars, history, and the old
URL preserved via GitHub's redirect). Folds in all fork work from v0.4.0 through
v0.8.0. Shipped as a pre-release (`v0.9.0-beta.1`) for testing first.

### Changed

- Project home is now `AsimovMac/asimov`; release tooling, README, and install
  scripts retargeted accordingly

## [0.8.0] — 2026-06-19

### Added

- `--no-read-cache` and `--no-write-cache` flags that control the cache on two independent axes. `--no-read-cache` ignores all cached state (re-discovers and re-verifies everything, then rebuilds the cache); `--no-write-cache` reads the cache but persists nothing. `--full-scan` is now an alias for `--no-read-cache`, and `--no-cache` an alias for both together — both kept for backwards compatibility

### Changed

- `--full-scan` now re-evaluates **everything**: it ignores the `excluded` and `failed` state too (not just `paths`/`mdfind_seen`), so a path you manually un-excluded, or a previously failed path, is re-checked against the `tmutil isexcluded` ground truth. Previously it still trusted the `excluded` cache and skipped those paths
- `--no-cache` now honors its documented contract — it reads **and** writes nothing. Previously it still read and wrote the `excluded`/`failed` state files
- `--full-scan` and `--no-cache` are no longer mutually exclusive (combining them is well-defined: both reads and writes are skipped); the previous "mutually exclusive" error is removed

### Fixed

- Security: a wildcard sentinel value from `~/.config/asimov/config` (`[sentinels] extra`) was interpolated unquoted into a `find -execdir sh -c …` string, so a crafted value like `*.x'; cmd; '` could run arbitrary commands during a scan. The glob is now passed as a positional argument and never re-parsed as shell code (globbing still works); built-in sentinels were unaffected
- Persistent `failed`-state (`~/.cache/asimov/failed`) is now deduplicated each run like the other caches, instead of growing by a duplicate line on every run that hits a `tmutil` failure (e.g. Go `@`-module paths)
- `scripts/install.sh` / `scripts/uninstall.sh` now resolve `asimov` and the plist relative to the script's own location (via `BASH_SOURCE`) instead of the caller's working directory, so `make install`/`uninstall` no longer depend on being run from the repo root
- Hardening: `asimov` sets `umask 077` so its temp files (which list the full home-directory layout) and its `~/.cache/asimov` state are created private to the user
- `--dry-run` now takes the exact same code path as a real run: it runs the read-only `tmutil isexcluded` ground-truth guard instead of stopping at the Spotlight cache, then prints `Would exclude` (and never persists state or calls `addexclusion`). Previously the preview over-reported, listing directories that a real run would skip — most visibly a dependency dir already covered by a manually excluded ancestor (e.g. `~/.nvm`), since path-based Time Machine exclusions aren't reported by Spotlight ([#19](https://github.com/django23/asimov/issues/19))
- `make bump-formula` no longer commits a bad Homebrew formula when the release tarball download fails. The old `curl … | shasum | awk` pipeline swallowed a failed `curl` (pipeline exit status came from `awk`), so a transient network error produced the SHA-256 of an empty string (`e3b0c4…b855`) — which slipped past the all-zeros guard and was committed/pushed to the tap, breaking `brew install`. Now downloads to a temp file with an explicit failure check, rejects an empty tarball, enables `pipefail`, and rejects the empty-string hash. Surfaced during the 0.7.0 release

### Removed

## [0.7.0] — 2026-06-18

### Added

- moonrepo: exclude `.moon/cache` when a `workspace.yml` sits beside it
- CONTRIBUTING.md: troubleshooting entry for `make prep-release` failing on a dirty tree when the uncommitted changes ARE the release content (manual fallback)

### Changed

- README: surface user-defined sentinels prominently — a new **Add your own patterns** subsection explains the `directory sentinel` format with examples, and a pointer under the ecosystems table sends readers there. Custom exclusion patterns were already supported via `[sentinels] extra`; this just makes them discoverable
- Makefile pins `gh` to `django23/asimov` via `export GH_REPO`, so a configured `upstream` remote (e.g. `stevegrunwell/asimov`) can no longer hijack release-flow gh calls. Surfaced during the 0.6.4 release when `make ship-formula` 404'd against the upstream `release.yml` and `gh pr create --fill` failed to compute a diff range
- `make verify-release` now invokes `$(brew --prefix asimov)/bin/asimov --version` directly instead of bare `asimov`, so an older binary earlier on `PATH` no longer hides the freshly-installed version

### Fixed

- README badges restored — the 0.6.4 README rewrite stripped the `![…](badge.svg)` image syntax, leaving plain text links instead of the Tests / Latest release / Stars / macOS / License / Shell shields

### Removed

## [0.6.4] — 2026-05-01

### Added

- `make prep-release VERSION=X.Y.Z` (backed by `scripts/prep-release.sh`) — bumps `ASIMOV_VERSION`, promotes `[Unreleased]` in CHANGELOG with compare links, runs `make check`, and commits on a `release/X.Y.Z` branch. Removes the two manual edit steps that were the most error-prone part of the release flow
- `make ship-formula` — waits for `release.yml` to finish, runs `bump-formula`, and pushes the Homebrew tap. Replaces the `sleep 6` + `gh run watch` recipe that previously lived only in CONTRIBUTING.md
- `make verify-release` — `brew upgrade asimov` (or install) + `asimov --version`

### Changed

- CONTRIBUTING.md release flow trimmed from a 4-step prose narrative to ~10 commands; the orchestration now lives in Makefile targets so an AI agent (or human) can execute the release end-to-end without re-deriving sed scripts or watch loops
- README rewritten with an outcome-first hook, worktree/AI-coding angle, and a "What you'll see" sample run; install moved above the explainer to lower friction, and the `--stats` flag is now documented in the Usage table

### Fixed

### Removed

## [0.6.3] — 2026-04-21

### Changed

- README: added "Latest release" and "Stars" badges alongside the existing Tests / macOS / License / Shell badges so progress and social proof are visible at a glance

## [0.6.2] — 2026-04-20

### Fixed

- `SECURITY.md`: replaced invalid `django23@github.com` contact with the project maintainer's GitHub noreply address so vulnerability reports no longer bounce
- README: Uninstall section used legacy `launchctl unload`; replaced with modern `launchctl bootout` to match the Schedule section

## [0.6.1] — 2026-04-20

### Changed

- README: moved Usage section above Schedule so the core command reference comes before scheduling details

## [0.6.0] — 2026-04-20

### Added

- Persistent path cache (`~/.cache/asimov/paths`) that stores discovered dependency paths across runs. Subsequent runs skip the full `find` traversal entirely, reducing runtime from ~75s to ~1-2s on typical home directories
- Incremental Spotlight discovery via `mdfind` to find newly created projects without traversing the filesystem
- `--full-scan` flag to force a full filesystem scan, ignoring any existing cache
- `--no-cache` flag to run a full scan without reading or writing cache
- `--stats` flag to show per-directory sizes and a total-space summary (opt-in, replaces previous always-on behaviour)
- Optional positional `[directory]` argument to scope the scan to a specific directory instead of the full home directory
- `make bench` target to compare dry-run timing against `tests/fixture/` across versions
- `make bench-home` target to compare dry-run timing against the real home directory across versions
- `tests/fixture/` directory with representative project structures for correctness checks and benchmarking
- Persistent excluded-path state (`~/.cache/asimov/excluded`) that tracks successful `tmutil addexclusion` calls across runs. Handles interrupted runs and Spotlight indexing delays — paths excluded in a previous run are never re-excluded, even if Spotlight hasn't indexed them yet
- Persistent failed-path state (`~/.cache/asimov/failed`) that remembers paths where `tmutil addexclusion` fails (e.g. Go module paths with `@` characters). Failed paths are automatically skipped on subsequent runs instead of retrying; use `--full-scan` to retry
- Persistent mdfind-seen cache (`~/.cache/asimov/mdfind_seen`) that remembers all candidates checked by Spotlight discovery. Directories without sentinels (false positives) are not re-checked on subsequent runs, eliminating ~1,200 redundant sentinel lookups per cached run

### Changed

- Default run with an existing cache now uses the cache instead of a full `find` traversal; use `--full-scan` to force re-traversal
- Directory sizes and "totalling" summary are no longer computed by default; use `--stats` to enable them. Removes the `du -sk` call per matched directory, significantly reducing wall-clock time on large home directories.
- Already-excluded paths are now filtered via a fast cache lookup (`grep`) instead of adding per-path `-not -prune` clauses to `find`. Removes the O(directories × excluded_paths) overhead that dominated scan time on large home directories. Speed improvements of 37%
- `tmutil addexclusion` uses per-path calls instead of batch to avoid wasting minutes when a single path fails (e.g. Go module paths with `@` characters). Batch mode provided no speed benefit — tmutil processes paths sequentially at ~11s each regardless
- Paths that are descendants of fixed dirs (e.g. `~/.cache`) are skipped during sentinel-based exclusion since the fixed dir will be excluded unconditionally
- Nested dependency paths are automatically deduplicated — if a parent directory is excluded, its descendants are skipped since Time Machine exclusions are recursive
- Full scan now streams `find` output through `tee` to write the cache incrementally; an interrupted scan leaves a partial cache that accelerates the next run
- Spotlight incremental discovery now bulk-filters cached paths with a single `grep -Fxvf` instead of one `grep` subprocess per candidate, and uses bash parameter expansion instead of `dirname`/`basename` subprocesses — eliminates ~27,000 subprocess spawns on typical home directories
- Spotlight discovery now prefix-filters candidates nested under cached paths before sentinel checking — eliminates thousands of redundant sentinel lookups (e.g. `node_modules/dep/node_modules` under an already-cached `node_modules`)
- Spotlight discovery uses temp files instead of bash string variables for large datasets — avoids slow `printf` on 15K-line strings
- Spotlight discovery now runs descendant filter before exact-match filter and uses `sort`+`comm` instead of `grep -Fxvf` for set difference — BSD `grep -Fxvf` is O(n×m) and took 35s on 15K candidates; `sort`+`comm` is O(n log n) and takes <1s
- Excluded-path filtering now uses a single bulk `grep -Fxvf` instead of per-path subprocess spawns
- Default branch renamed to `main` (was `develop`); branch protection requires signed commits + passing CI
- CI workflow now runs on every PR (including from forks), not just specific base branches
- `make release` is now strict: requires clean tree, must be on `main`, signed tags only
- Added `make bump-formula` to update the Homebrew tap (`django23/homebrew-tap`) after a release

### Fixed

### Removed

## [0.5.0] — 2026-03-02

### Added

- `--quiet` flag to suppress all non-error output
- `--verbose` flag to show already-excluded directories (hidden by default)
- Config file support (`~/.config/asimov/config`) for enabling fixed dirs, adding extra dirs/sentinels, and disabling built-in sentinels
- Curl-based installer (`scripts/install-remote.sh`) for non-Homebrew users
- Unit tests for `format_size_kb()` boundary values
- Flag combination tests (`--dry-run --verbose`, `--dry-run --quiet`)
- GitHub issue/PR templates
- `SECURITY.md` with private vulnerability reporting instructions
- `UPGRADING.md` with migration guide from v0.4.x and original asimov

### Changed

- **BREAKING:** Fixed dirs (global caches) are now opt-in via config file (previously always on)
- **BREAKING:** LaunchAgent label renamed from `com.stevegrunwell.asimov` to `com.django23.asimov`
- Colors are now disabled when stdout is not a terminal (e.g. launchd, pipes)
- `tmutil isexcluded` check removed from default path (now `--verbose`-only); mdfind optimization already prunes excluded paths
- `record_excluded_path()` calls `du` once instead of twice per path
- `format_size_kb()` uses bash arithmetic instead of spawning `awk`
- Simplified `print_exclusion_summary()` to a single printf with early return
- Removed stale `@version` header comment
- Removed unnecessary defensive guards on always-initialized variables
- Mock tmutil now idempotent (matches real tmutil behavior)
- README rewritten with concise install-first structure
- Updated all repo URLs from stevegrunwell/asimov to django23/asimov

### Removed

- `tmutil isexcluded` per-path check in default (non-verbose) mode

## [0.4.0] — 2025-02-20

### Added

* Validation that `ASIMOV_ROOT` exists and is a directory before running (clear error and exit 1 if not)
* Test for project paths containing spaces; test for dry-run summary format (count and size)
* `--help` and `--version` options; unknown options exit with an error and usage message
* `--dry-run` option to print what would be excluded without calling `tmutil`
* Support glob patterns in sentinel definitions, enabling wildcards like `*.xcodeproj` ([stevegrunwell/asimov#64], props @mdab121)
* Exclude Xcode DerivedData when `*.xcodeproj` is present ([stevegrunwell/asimov#64], props @mdab121)
* Exclude well-known global cache directories (`~/.cache`, `~/.gradle/caches`, `~/.m2/repository`, `~/.npm/_cacache`, `~/.nuget/packages`, `~/.kube/cache`, etc.) without requiring sentinel files (inspired by [stevegrunwell/asimov#69], props @pkuczynski)
* Display a summary of total count and size of newly excluded directories at the end of each run (inspired by [stevegrunwell/asimov#84], props @Vadorequest)
* Exclude Next.js build cache (`.next`)
* Exclude Nuxt build cache (`.nuxt`)
* Exclude Angular CLI cache (`.angular`)
* Exclude SvelteKit build output (`.svelte-kit`)
* Exclude Turborepo cache (`.turbo`)
* Exclude Yarn Berry cache (`.yarn`)
* Exclude Leiningen/Clojure CLI `target` and `.cpcache` directories
* Exclude Shadow-CLJS cache (`.shadow-cljs`)
* Exclude Python virtualenv `venv` with `pyproject.toml` sentinel
* Exclude PEP 582/PDM local packages (`__pypackages__`)
* Exclude Elixir/Mix standard `_build` directory
* Exclude Terraform providers/modules (`.terraform` with `.terraform.lock.hcl`)
* Exclude direnv output (`.direnv`)
* Exclude OCaml/Dune build output (`_build`)
* Exclude Zig build cache (`.zig-cache`) and output (`zig-out`)
* Exclude Elm packages (`elm-stuff`)
* Exclude Godot 4 editor cache (`.godot`)
* Exclude R renv environment (`renv`)
* Exclude .NET build output (`bin`, `obj`) when `*.csproj` or `*.fsproj` project files are present (inspired by [stevegrunwell/asimov#87], props @guigomesa)
* Added `make install` and `make uninstall` targets for streamlined setup and removal ([#35], props @sylver)
* Added `scripts/uninstall.sh` to cleanly remove Asimov and its launchd schedule ([#35], props @sylver)
* Added common interval reference comments to `com.stevegrunwell.asimov.plist` ([#35], props @sylver)
* Dropped macOS 13 from the CI test matrix (runner was retired December 2025)


### Changed

* Use `ASIMOV_ROOT` in `ASIMOV_SKIP_PATHS` and `ASIMOV_FIXED_DIRS` so skip/fixed paths are correct when running as root (e.g. launchd)
* Refactor: extract `record_excluded_path()` for DRY size logging and output; `resolve_asimov_root()`, `build_find_skip_params()`, `build_find_vendor_params()`, `print_exclusion_summary()`, `format_size_kb()`; rename `exclude_file` to `exclude_paths_from_stdin`; add named constants for size and colors
* Skip non-directory paths in `exclude_paths_from_stdin` (avoids failures if a path disappears between find and processing)
* Use `printf` instead of `echo -e` in install/uninstall scripts for portability
* Skip directories already excluded from Time Machine backups for faster subsequent runs (inspired by [stevegrunwell/asimov#97], props @VladRassokhin)
* Migrated test suite from PHP/PHPUnit to [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System), removing the PHP dependency for contributors
* Replaced Travis CI pipeline with GitHub Actions (macOS 14 + 15 matrix)
* Replaced PHP `tmutil` mock with a pure bash implementation
* Moved install script to `scripts/install.sh` with shared variables, now copies binary instead of symlinking ([#35], props @sylver)

### Fixed

* Handle `tmutil` errors gracefully instead of crashing; paths that fail exclusion are skipped with a warning ([stevegrunwell/asimov#101], [stevegrunwell/asimov#86])
* Detect the logged-in user's home directory when running as root, fixing `brew services` and `sudo` invocations that would search `/var/root` instead ([stevegrunwell/asimov#72])
* Fixed duplicate Gradle sentinel entries in the sentinels list
* Fixed typo in comment ("decendents" → "descendants")

### Removed

* Removed PHP test infrastructure (`composer.json`, `phpunit.xml.dist`, and PHP test files)
* Removed Travis CI configuration (`.travis.yml`)

[0.4.0]: https://github.com/django23/asimov/compare/v0.3.0...v0.4.0

## [Version 0.3.0] — 2020-06-16

### Added

* Added Homebrew support 🙌 ([#34], props @Dids)
* Exclude Bower dependencies ([#22], props @moezzie)
* Exclude Maven builds ([#30], props @bertschneider)
* Exclude Stack dependencies ([#32], props @alex-kononovich)
* Exclude Carthage dependencies ([#37], props @qvacua)
* Exclude CocoaPods dependencies and Swift builds ([#43], props @slashmo)
* Exclude Bundler, Cargo, and Dart dependencies ([#56])
* Define a [Travis CI pipeline for Asimov](https://travis-ci.com/github/stevegrunwell/asimov) ([#20])
* Add an automated test suite using PHPUnit ([#31])

### Fixed

* Removed an extraneous `read -r path`, which was causing the first match to be skipped ([#15], props @rowanbeentje)
* Use the full system path when running `chmod` in `install.sh` ([#33], props @ko-dever)

### Changed

* The size of the excluded directories are now included in the Asimov output ([#16], props @rowanbeentje)
* Switch to using find's -prune switch to exclude match subdirectories for speed, and exclude ~/Library folder from searches ([#17], props @rowanbeentje)
* Rework the `find` command and path variables so that `find` is only run once however many FILEPATHS are set ([#18], @props @rowanbeentje, yet again 😉)
 Fix incorrect directory pruning, simplify path handling ([#36], props @rwe)
* Recommend cloning via HTTPS rather than SSH for manual installations ([#52], props @Artoria2e5)
* Don't look for matches in `~/.Trash` ([#55])


## [Version 0.2.0] — 2017-11-25

### Added

* Bundle the script with `com.stevegrunwell.asimov.plist`, enabling Asimov to be scheduled to run daily. Users can set this up in a single step by running the new `install.sh` script.
 Added a formal change log to the repository. ([#5])

### Fixed

* Fixed pathing issue when resolving the script directory for `install.sh`. Props @morganestes. ([#7])

### Changed
* Change the scope of Asimov to find matching directories within the current user's home directory, not just `~/Sites`. Props to @vitch for catching this! ([#10]).


## [Version 0.1.0] — 2017-10-17

Initial public release.


[Unreleased]: https://github.com/AsimovMac/asimov/compare/v0.9.0...main
[0.9.0]: https://github.com/AsimovMac/asimov/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/django23/asimov/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/django23/asimov/compare/v0.6.4...v0.7.0
[0.6.4]: https://github.com/django23/asimov/compare/v0.6.3...v0.6.4
[0.6.3]: https://github.com/django23/asimov/compare/v0.6.2...v0.6.3
[0.6.2]: https://github.com/django23/asimov/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/django23/asimov/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/django23/asimov/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/django23/asimov/compare/v0.4.0...v0.5.0
[stevegrunwell/asimov#10]: https://github.com/stevegrunwell/asimov/issues/10
[stevegrunwell/asimov#15]: https://github.com/stevegrunwell/asimov/pull/15
[stevegrunwell/asimov#16]: https://github.com/stevegrunwell/asimov/pull/16
[stevegrunwell/asimov#17]: https://github.com/stevegrunwell/asimov/pull/17
[stevegrunwell/asimov#18]: https://github.com/stevegrunwell/asimov/pull/18
[stevegrunwell/asimov#20]: https://github.com/stevegrunwell/asimov/pull/20
[stevegrunwell/asimov#22]: https://github.com/stevegrunwell/asimov/pull/22
[stevegrunwell/asimov#30]: https://github.com/stevegrunwell/asimov/pull/30
[stevegrunwell/asimov#31]: https://github.com/stevegrunwell/asimov/pull/31
[stevegrunwell/asimov#32]: https://github.com/stevegrunwell/asimov/pull/32
[stevegrunwell/asimov#33]: https://github.com/stevegrunwell/asimov/pull/33
[stevegrunwell/asimov#34]: https://github.com/stevegrunwell/asimov/pull/34
[stevegrunwell/asimov#36]: https://github.com/stevegrunwell/asimov/pull/36
[stevegrunwell/asimov#37]: https://github.com/stevegrunwell/asimov/pull/37
[stevegrunwell/asimov#43]: https://github.com/stevegrunwell/asimov/pull/43
[stevegrunwell/asimov#52]: https://github.com/stevegrunwell/asimov/pull/52
[stevegrunwell/asimov#55]: https://github.com/stevegrunwell/asimov/pull/55
[stevegrunwell/asimov#35]: https://github.com/stevegrunwell/asimov/pull/35
[stevegrunwell/asimov#56]: https://github.com/stevegrunwell/asimov/pull/56
[stevegrunwell/asimov#64]: https://github.com/stevegrunwell/asimov/pull/64
[stevegrunwell/asimov#69]: https://github.com/stevegrunwell/asimov/pull/69
[stevegrunwell/asimov#86]: https://github.com/stevegrunwell/asimov/issues/86
[stevegrunwell/asimov#87]: https://github.com/stevegrunwell/asimov/pull/87
[stevegrunwell/asimov#97]: https://github.com/stevegrunwell/asimov/pull/97
[stevegrunwell/asimov#5]: https://github.com/stevegrunwell/asimov/issues/5
[stevegrunwell/asimov#7]: https://github.com/stevegrunwell/asimov/issues/7
[stevegrunwell/asimov#72]: https://github.com/stevegrunwell/asimov/issues/72
[stevegrunwell/asimov#84]: https://github.com/stevegrunwell/asimov/issues/84
[stevegrunwell/asimov#101]: https://github.com/stevegrunwell/asimov/issues/101
