# Test setup: Copybara imports a library, evolvectl fixes the callers

A small Go monorepo, built from copies of its libraries under `third_party/`. Two libraries are upgraded, and each run follows the same flow:

1. **Copybara** copies only the needed files of the new library version into `third_party/<lib>/v2/`.
2. Nothing else changes, so the services still use the old copy. Switching them to the new copy by hand gives compile errors.
3. **evolvectl** lists what broke (`impact`), then moves the imports, fixes each call, updates `go.mod`, and runs the tests before and after (`upgrade`).

| Library | Monorepo has today | Copybara brings in | What breaks in the callers |
| --- | --- | --- | --- |
| gax-go (real, from GitHub) | `third_party/gax-go`, the 2016 copy (`v0.0.0-20161107002406-da06d194a00e`) | `v2.0.2`: 4 source files, `go.mod`, `go.sum`, `LICENSE` into `third_party/gax-go/v2` | import path is `/v2`; `gax.APICall` takes a `gax.CallSettings` parameter, so the closure passed to `gax.Invoke` stops compiling |
| acme/retry (demo, in `libs/`) | `third_party/acme-retry`, v1.0.0 | `v2.0.0`: `retry.go`, `go.mod`, `LICENSE` into `third_party/acme-retry/v2` | import path is `/v2`; `Config.MaxTries` renamed to `MaxAttempts`; `DefaultConfig()` renamed to `Default()`; the function passed to `Do` takes an `attempt int` |

The gax fixes come from recipes bundled with evolvectl. The acme fixes come from the three recipes in `monorepo/recipes/acme-retry/`, which a library team would ship with its release.

## Layout

| Path | What it is |
| --- | --- |
| `monorepo/` | the monorepo as it is today: `services/speech` calls gax-go, `services/orders` calls acme/retry, with old copies in `third_party/` and `replace` lines in `go.mod` |
| `libs/acme-retry/v1.0.0`, `v2.0.0` | the source of the demo library at each version. `setup` turns them into a git repository with two tags |
| `copy.bara.sky` | two workflows, `import_gax_go` and `import_acme_retry`. Each one owns only its `third_party/<lib>/v2/**` folder |
| `demo.ps1` | runs each step |
| `out/` | made by `setup`, ignored by git, deleted by `reset` |

## Commands

[EVOLVECTL-COMMANDS.md](EVOLVECTL-COMMANDS.md) lists each evolvectl and Copybara command one by one, with the result it gave. The script below runs the same commands.

Run from the `copybara-testing` folder, in PowerShell.

```powershell
./test/demo.ps1 check                 # git, go, java, bazelisk, copybara, evolvectl
./test/demo.ps1 setup                 # out/acme-retry, out/monorepo.git, out/monorepo, out/copy.bara.sky
./test/demo.ps1 build                 # today: builds, 4 tests pass

# 1. Copybara brings the new library files in
./test/demo.ps1 preview               # what each import adds (evolvectl, no Copybara)
./test/demo.ps1 validate              # copybara validate
./test/demo.ps1 dry-run -Library gax  # copybara migrate --dry-run
./test/demo.ps1 migrate -Library gax  # copybara migrate, then git pull in out/monorepo
./test/demo.ps1 migrate -Library retry
#   no Copybara on this machine? use: ./test/demo.ps1 simulate

# 2. See what breaks
./test/demo.ps1 build                 # still passes: the services use the old copy
./test/demo.ps1 break                 # switch by hand in out/break: compile errors
./test/demo.ps1 impact                # evolvectl: changed API and each call site

# 3. evolvectl fixes the callers
./test/demo.ps1 upgrade -DryRun       # on a temporary copy
./test/demo.ps1 upgrade               # edits out/monorepo and commits each library
git -C test/out/monorepo log --oneline
git -C test/out/monorepo show HEAD~1  # the gax-go fix
git -C test/out/monorepo show HEAD    # the acme/retry fix

./test/demo.ps1 reset                 # delete out/ and start again
```

The HTML report of each run is in `test/out/monorepo/.evolvectl/runs/<run id>/report.html`.

To run evolvectl by hand in `test/out/monorepo`:

```powershell
cd test/out/monorepo
evolvectl impact  github.com/acme/retry --to v2.0.0 --to-module github.com/acme/retry/v2 --use-dir third_party/acme-retry/v2
evolvectl upgrade github.com/acme/retry --to v2.0.0 --to-module github.com/acme/retry/v2 --use-dir third_party/acme-retry/v2
evolvectl impact  github.com/googleapis/gax-go --to v2.0.2 --to-module github.com/googleapis/gax-go/v2 --use-dir third_party/gax-go/v2
evolvectl upgrade github.com/googleapis/gax-go --to v2.0.2 --to-module github.com/googleapis/gax-go/v2 --use-dir third_party/gax-go/v2
```

`--use-dir` tells evolvectl the new version is already in the repository, where Copybara put it. evolvectl adds a `replace` to that folder and never downloads the library. evolvectl refuses to start on a worktree with uncommitted changes, which is why `demo.ps1 upgrade` commits after each library.

## Verified on this machine

The Copybara config passes `copybara validate`. No Copybara `migrate` or `dry-run` was run. The `simulate` step stood in for the import: it writes the files the workflow would write, found with `evolvectl copybara preview`. Then both upgrades ran from a clean `out/`:

- Before: 4 tests passed. After each upgrade: 4 tests passed, coverage unchanged.
- `break` gives these compile errors when only go.mod and the imports are switched: `undefined: retry.DefaultConfig`, `unknown field MaxTries`, the `retry.Do` closure has the wrong type (twice), and the `gax.Invoke` closure is not a `gax.APICall`.
- Both upgrades finish as `succeeded_with_review` (exit 6). Review items:
  - The old `replace` line for each library is still in go.mod. Delete it, and the old `third_party` folder, when nothing uses them.
  - For gax only: go.mod requires `gax-go/v2 v2.22.0`, not `v2.0.2`. `google.golang.org/grpc` v1.84.0 requires at least v2.22.0, so `go mod tidy` raises the version. The `replace` still builds the imported v2.0.2 copy.

The monorepo needs Go 1.26 or newer, because the gRPC version it resolves (v1.84.0) requires it. The monorepo has no Bazel BUILD files. evolvectl reads `go.mod` and runs `go test`; it does not run Bazel.
