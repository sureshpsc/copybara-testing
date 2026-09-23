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

```powershell
$env:Path += ";C:\Users\sures\go\bin"
$env:HOME = "C:\Users\sures"
copybara migrate "C:\Users\sures\copybara-testing\copybara-config\copy.bara.sky" --force
```

## Bazel verification

```powershell
cd C:\Users\sures\copybara-testing\copybara
bazelisk query //java/com/google/copybara:copybara
```

## Why this is set up this way

- The upstream Go monorepo is intentionally left as a local clone so a large dependency graph can be inspected without adding the whole project to the GitHub repository history.
- The Copybara config focuses on Go dependency manifests and source files, making it straightforward to update transitive dependency references as part of a packaging flow.
- Bazel is configured through Bazelisk so the workspace uses the correct Bazel version without manual installation drift.
