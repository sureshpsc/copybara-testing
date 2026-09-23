$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$otelRepo = Join-Path $repoRoot 'opentelemetry-collector-contrib'
$copybaraRepo = Join-Path $repoRoot 'copybara'
if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }

if (-not (Test-Path (Join-Path $otelRepo 'go.mod'))) {
    throw "OpenTelemetry Go monorepo not found at $otelRepo. Clone it first: git clone https://github.com/open-telemetry/opentelemetry-collector-contrib.git"
}

$copybaraMarker = @(
    (Join-Path $copybaraRepo 'WORKSPACE'),
    (Join-Path $copybaraRepo 'WORKSPACE.bazel'),
    (Join-Path $copybaraRepo 'MODULE.bazel')
)
if (-not ($copybaraMarker | Where-Object { Test-Path $_ })) {
    throw "Copybara source checkout not found at $copybaraRepo. Clone it first: git clone https://github.com/google/copybara.git"
}

Write-Host 'Checking Go module graph...'
Set-Location $otelRepo
$moduleSample = go list -m all | Select-Object -First 20
$moduleSample | ForEach-Object { Write-Host $_ }

Write-Host ''
Write-Host 'Checking Bazel target resolution...'
Set-Location $copybaraRepo
bazelisk query //java/com/google/copybara:copybara | Select-Object -First 20 | ForEach-Object { Write-Host $_ }

Write-Host ''
Write-Host 'Validating Copybara config...'
copybara validate (Join-Path $repoRoot 'copybara-config\copy.bara.sky')

Write-Host ''
Write-Host 'Copybara config is available at:'
Write-Host (Join-Path $repoRoot 'copybara-config\copy.bara.sky')
