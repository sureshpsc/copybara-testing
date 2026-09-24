# Copybara/Bazel Go dependency packaging setup

This repository is a lightweight workspace for preparing a Go-based OpenTelemetry monorepo and a Copybara-driven dependency update flow.

## Local layout

- `opentelemetry-collector-contrib/` - local clone of the upstream Go monorepo used as the source of truth for dependency updates.
- `copybara/` - local clone of the upstream Copybara source used to validate Bazel targets and Copybara builds.
- `copybara-config/copy.bara.sky` - Copybara Sky workflow used to mirror and rewrite Go module dependencies.
- `internal-otel-contrib/` - local bare destination repository used for Copybara pushes during validation.
- `scripts/local-smoke.ps1` - quick local validation script for the Go module graph and Bazel resolution.

## Quick validation

From the repo root:

```powershell
./scripts/local-smoke.ps1
```

## Copybara execution

`copy.bara.sky` has three workflows. Name the one you want:

| Workflow | Copies | Into |
| --- | --- | --- |
| `sync_otel_contrib_go_packages` | the otel monorepo, with module paths rewritten to `github.com/acme/...` | `internal-otel-contrib`, everything except top-level `third_party/` |
| `import_gax_go` | `v2/` and `LICENSE` of github.com/googleapis/gax-go at `gax_ref` | `internal-otel-contrib`, only `third_party/gax-go/v2/` |
| `import_gax_go_folder` | the same gax-go files | a plain folder given by `--folder-dir` |

```powershell
$env:HOME = $env:USERPROFILE
copybara migrate copybara-config/copy.bara.sky sync_otel_contrib_go_packages --git-destination-url file:///<repo>/internal-otel-contrib --force
```

## gax-go import (ready to run on another machine)

The otel Google Cloud components call gax-go. `receiver/googlecloudpubsubreceiver`, `exporter/googlecloudpubsubexporter`, and `confmap/provider/googlesecretmanagerprovider` require `github.com/googleapis/gax-go/v2 v2.24.1` directly, and about 18 more modules pull it in indirectly. The `import_gax_go` workflow copies that library into `third_party/gax-go/v2/` of the internal destination, next to the otel code, so an upgrade can be reviewed and tested in one place.

Nothing has been migrated yet. The config validates (`copybara validate` passes) and `evolvectl copybara preview` shows the files each version would write:

| `gax_ref` | Upstream commit | Files written |
| --- | --- | --- |
| `v2.24.1` (the config default, what otel uses) | `269185f` | 66 |
| `v2.0.2` (the Pod 1 sheet target) | `b001040` | 10 |

### On the other machine

1. Clone with submodules and check the tools.

   ```powershell
   git clone --recurse-submodules https://github.com/sureshpsc/copybara-testing.git
   cd copybara-testing
   ./scripts/gax-import.ps1 check
   ```

   evolvectl is installed from its own checkout: `git clone https://github.com/sureshpsc/evolvectl.git`, then `go install ./cmd/evolvectl` inside it. Copybara runs from `copybara` on `PATH`, or `$env:COPYBARA`, or the `copybara/` submodule through `bazelisk`, which also needs a JDK.

2. See what the import would do. These steps change nothing.

   ```powershell
   ./scripts/gax-import.ps1 preview                 # files at gax_ref, no Copybara or Java needed
   ./scripts/gax-import.ps1 preview -Ref v2.0.2     # try another version without editing the config
   ./scripts/gax-import.ps1 validate                # copybara validate
   ```

3. Import into a folder first. No destination repository is needed.

   ```powershell
   ./scripts/gax-import.ps1 folder                  # writes out/gax-go/third_party/gax-go/v2
   ```

4. Import into the destination repository.

   ```powershell
   ./scripts/gax-import.ps1 setup                   # creates internal-otel-contrib/ (bare, empty)
   ./scripts/gax-import.ps1 dry-run -First          # -First only for the first import into this destination
   ./scripts/gax-import.ps1 migrate -First
   git clone internal-otel-contrib out/internal-otel-contrib
   ```

   The script passes `--git-destination-url` with this machine's path, so the `destination_url` written in the config never has to be edited. `-First` adds `--force`, which Copybara needs when the destination has no earlier import to continue from.

5. Move to another gax-go version.

   ```powershell
   ./scripts/gax-import.ps1 pin -Ref v2.24.0        # edits gax_ref and prints the diff
   evolvectl copybara preview --config copybara-config/copy.bara.sky --workflow import_gax_go --against out/internal-otel-contrib
   ./scripts/gax-import.ps1 migrate
   ```

   `--against` lists what the new version adds, changes, and deletes inside `third_party/gax-go/v2/` of the destination checkout.

6. Check the callers. Copybara only copies the library. Point one real otel module in the `opentelemetry-collector-contrib` submodule at the imported copy and build it. The destination checkout cannot be built directly, because its module paths are rewritten to `github.com/acme/...`.

   ```powershell
   cd opentelemetry-collector-contrib/receiver/googlecloudpubsubreceiver
   go mod edit -replace github.com/googleapis/gax-go/v2=../../../out/gax-go/third_party/gax-go/v2
   go build ./...
   go test ./...
   git checkout -- go.mod go.sum                    # undo the replace
   ```

   The path above uses the step 3 folder import. Before any import, `../../../.evolvectl/copybara/import_gax_go/third_party/gax-go/v2` (the `preview` output) works the same way; this was checked at v2.24.1 and `go build ./...` passed. When `gax_ref` moves past what otel requires, `evolvectl upgrade github.com/googleapis/gax-go/v2 --to <tag> --dry-run` in that module runs the tests before and after and reports what needs fixing.

The two workflows share one destination safely. `sync_otel_contrib_go_packages` excludes top-level `third_party/**` from its `destination_files`, and `import_gax_go` owns only `third_party/gax-go/v2/**`. Without that exclusion, the next otel sync would delete the gax import.

## Test monorepo demo (Copybara import, then evolvectl fixes the callers)

`test/` has a small monorepo with old copies of gax-go and a demo library, `acme/retry`, in `third_party/`. Copybara imports the new version of each one. evolvectl then fixes the code that calls them and runs the tests before and after. See [test/README.md](test/README.md); every step runs through `./test/demo.ps1`.

## Bazel verification

```powershell
cd C:\Users\sures\copybara-testing\copybara
bazelisk query //java/com/google/copybara:copybara
```

## Why this is set up this way

- The upstream Go monorepo is intentionally left as a local clone so a large dependency graph can be inspected without adding the whole project to the GitHub repository history.
- The Copybara config focuses on Go dependency manifests and source files, making it straightforward to update transitive dependency references as part of a packaging flow.
- Bazel is configured through Bazelisk so the workspace uses the correct Bazel version without manual installation drift.
