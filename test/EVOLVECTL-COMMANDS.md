# evolvectl commands for the test monorepo

Every command below was run on the test monorepo, and the results shown are from those runs. The flow for each library is: Copybara copies the new version into `third_party/<lib>/v2/`, then evolvectl finds and fixes the code that calls it.

`./test/demo.ps1` runs the same commands for you. This page lists them one by one, so you can type them yourself or adapt them to another repository.

## Before you start

| Need | How |
| --- | --- |
| Go 1.26 or newer | the monorepo resolves `google.golang.org/grpc` v1.84.0, which needs it |
| evolvectl with `--use-dir` | in your evolvectl checkout: `go install ./cmd/evolvectl`, then `evolvectl version` |
| git | for the local repositories |
| Copybara (only for the import step) | on `PATH`, or `$env:COPYBARA`, or the `copybara/` submodule with `bazelisk` and a JDK |

Create the local repositories once, from the `copybara-testing` folder:

```powershell
./test/demo.ps1 setup
cd test/out/monorepo        # every evolvectl command below runs here
```

`setup` creates these folders:

| Folder | What it is |
| --- | --- |
| `test/out/monorepo` | your checkout of the monorepo; evolvectl edits it |
| `test/out/monorepo.git` | the repository Copybara pushes to |
| `test/out/acme-retry` | the demo library, tags `v1.0.0` and `v2.0.0` |
| `test/out/copy.bara.sky` | the Copybara config with this machine's paths |

The two libraries:

| | gax-go | acme/retry |
| --- | --- | --- |
| Old module (today) | `github.com/googleapis/gax-go` | `github.com/acme/retry` |
| Old version | `v0.0.0-20161107002406-da06d194a00e` | `v1.0.0` |
| New module | `github.com/googleapis/gax-go/v2` | `github.com/acme/retry/v2` |
| New version | `v2.0.2` | `v2.0.0` |
| Imported into | `third_party/gax-go/v2` | `third_party/acme-retry/v2` |
| Copybara workflow | `import_gax_go` | `import_acme_retry` |
| Caller that breaks | `services/speech/speech.go` | `services/orders/orders.go` |

## Step 0: check the recipes and the repository

```powershell
evolvectl recipe test recipes
evolvectl scan
evolvectl outdated
```

- `recipe test` prints `PASS` for `acme.retry.default-config`, `acme.retry.do-attempt`, and `acme.retry.max-attempts`. The gax recipes ship inside evolvectl.
- `scan` finds 5 Go projects: the monorepo, the two old `third_party` copies, and the two v2 copies once they are imported.
- `outdated` lists `github.com/acme/retry v1.0.0` and the 2016 gax-go from `go.mod`. Add `--online` to ask the Go proxy for the latest versions and OSV for known vulnerabilities.

## Step 1: look at the import before running it

These commands read `copy.bara.sky`. They never run Copybara.

```powershell
evolvectl copybara list    --config ..\copy.bara.sky
evolvectl copybara explain --config ..\copy.bara.sky --workflow import_gax_go --file v2/invoke.go
evolvectl copybara preview --config ..\copy.bara.sky --workflow import_gax_go     --against . --out ..\preview\gax
evolvectl copybara preview --config ..\copy.bara.sky --workflow import_acme_retry --against . --out ..\preview\retry
```

- `explain` traces one upstream file: `v2/invoke.go` is included and lands at `third_party/gax-go/v2/invoke.go`.
- `preview` fetches the pinned ref with git and applies the workflow. Before the import it reports `7 added` for gax-go and `3 added` for acme/retry, all inside `third_party/<lib>/v2/`.

To try another version, change the ref. `--dry-run` shows the diff without writing it:

```powershell
evolvectl copybara pin --config ..\copy.bara.sky --workflow import_acme_retry --ref v1.0.0 --dry-run
evolvectl copybara preview --config ..\copy.bara.sky --workflow import_acme_retry --ref v1.0.0 --out ..\preview\v1
```

## Step 2: import with Copybara (not an evolvectl command)

Run these from the `copybara-testing` folder. `--force` is needed because the monorepo has no earlier Copybara import of these libraries to continue from.

```powershell
$env:HOME = $env:USERPROFILE
copybara validate test/out/copy.bara.sky
copybara migrate  test/out/copy.bara.sky import_gax_go     --dry-run --force
copybara migrate  test/out/copy.bara.sky import_gax_go     --force
copybara migrate  test/out/copy.bara.sky import_acme_retry --force
git -C test/out/monorepo pull --ff-only
```

Without Copybara, `./test/demo.ps1 simulate` commits the same files, taken from the `preview` output.

After the import, the services still build, because they still import the old paths. `./test/demo.ps1 break` switches go.mod and the imports by hand in a scratch copy, without fixing any code, and shows the compile errors. That is the work evolvectl does for you.

## Step 3: see what will break

```powershell
evolvectl impact github.com/acme/retry --to v2.0.0 --to-module github.com/acme/retry/v2 --use-dir third_party/acme-retry/v2
evolvectl impact github.com/googleapis/gax-go --to v2.0.2 --to-module github.com/googleapis/gax-go/v2 --use-dir third_party/gax-go/v2
```

`--use-dir` tells evolvectl the new version is already in the repository at that folder, where Copybara put it. `impact` compares the old copy with that folder. It downloads nothing and changes nothing.

| | acme/retry | gax-go |
| --- | --- | --- |
| API change | `DefaultConfig` removed; `Config` changed (`MaxTries` became `MaxAttempts`); `Do` changed (callback takes `attempt int`) | 7 removed (the `PathTemplate` API), `APICall` changed (takes `CallSettings`), `CallSettings` changed |
| Call sites | 4, all in `services/orders/orders.go` | 1, `services/speech/speech.go:13` (`Invoke`) |

Add `--format json` for the same data as JSON. `impact` reads declarations; it does not type-check. The line `cfg.MaxTries = 5` is not listed as a call site, but the upgrade still fixes it.

The plan shows the files, recipes, and risk:

```powershell
evolvectl plan github.com/acme/retry --to v2.0.0 --to-module github.com/acme/retry/v2 --use-dir third_party/acme-retry/v2
```

For acme/retry it shows 1 file, the 3 acme recipes, and risk low.

## Step 4: fix the callers

Try it on a temporary copy first. `--dry-run` leaves the checkout untouched:

```powershell
evolvectl upgrade github.com/googleapis/gax-go --to v2.0.2 --to-module github.com/googleapis/gax-go/v2 --use-dir third_party/gax-go/v2 --dry-run
```

Then run it for real. evolvectl refuses to start when the worktree has uncommitted changes, so commit after each library:

```powershell
evolvectl upgrade github.com/googleapis/gax-go --to v2.0.2 --to-module github.com/googleapis/gax-go/v2 --use-dir third_party/gax-go/v2
git add -A; git commit -m "Move callers to gax-go v2"

evolvectl upgrade github.com/acme/retry --to v2.0.0 --to-module github.com/acme/retry/v2 --use-dir third_party/acme-retry/v2
git add -A; git commit -m "Move callers to acme/retry v2"
```

Each upgrade:

1. adds `require <new module> <version>` and `replace <new module> => ./third_party/<lib>/v2` to go.mod
2. rewrites the imports to `/v2`
3. applies the recipes:
   - gax-go: the closure passed to `gax.Invoke` becomes `func(ctx context.Context, _ gax.CallSettings) error`
   - acme/retry: `DefaultConfig()` becomes `Default()`, `MaxTries` becomes `MaxAttempts`, and each `retry.Do` closure gets `_ int`
4. runs `go test` before and after. The result here: 4 passed before and 4 passed after, coverage unchanged.

Both finish as `succeeded_with_review`, exit code 6. The review items:

- `replace github.com/<old module> is still present`: remove the old replace line and the old `third_party` folder once nothing uses them.
- gax-go only: `requires github.com/googleapis/gax-go/v2 v2.22.0, not v2.0.2`. `google.golang.org/grpc` v1.84.0 requires at least v2.22.0, so `go mod tidy` raises the version in go.mod. The `replace` still builds the imported v2.0.2 copy. To make the two match, import a gax-go version of at least v2.22.0.

Exit codes: 0 all gates passed, 5 a required gate failed, 6 finished with review items, 9 the worktree has uncommitted changes.

## Step 5: review, report, undo

Every command prints a run id, such as `run_e6f5aebbec89e752`.

```powershell
evolvectl history                                   # all runs and their outcomes
evolvectl diff     --run <run id>                   # the patch
evolvectl validate --run <run id>                   # manifest-target, module-move, go test
evolvectl explain  --run <run id> services/orders/orders.go   # each change in that file and the recipe that made it
evolvectl report   --run <run id> --format html --output ..\report.html
evolvectl rollback --run <run id>                   # restore every file the run changed
```

The HTML report is also written to `.evolvectl/runs/<run id>/report.html`. `rollback` works while the files are still as the run left them. Run it before you commit or edit them.

## Start over

```powershell
cd ..\..\..                 # back to copybara-testing
./test/demo.ps1 reset
./test/demo.ps1 setup
```

## Using this on another repository

The same five steps work on any Go repository that keeps copies of its libraries in folders:

1. Copybara, or any sync tool, copies the new version into a folder with its own `go.mod`.
2. Run `evolvectl impact <old module> --to <version> --to-module <new module> --use-dir <folder>` to see what breaks.
3. Run `evolvectl upgrade` with the same flags to fix the callers and test them.
4. When the library team ships recipes (like `recipes/acme-retry/`), put them in the repository's `recipes/` folder. The bundled recipes cover gax-go and gRPC.
5. If recipe test files import the new module path, list their folder under `repository.ignore` in `.evolvectl.yaml`, so they are not treated as callers. The test monorepo does this with `recipes/**`.
