<#
.SYNOPSIS
  Import gax-go into the otel destination with Copybara, one step at a time.

.DESCRIPTION
  Every path is computed from this script's location, so the repository can live anywhere.
  Nothing is migrated unless you name the folder, dry-run, or migrate step.

  Steps, in the order you normally run them:
    check     show which tools are installed (git, go, java, bazelisk, copybara, evolvectl)
    setup     create the local bare destination repository internal-otel-contrib/
    preview   evolvectl copybara preview: the files the import would write (no Copybara, no Java)
    validate  copybara validate on the config
    folder    copybara migrate import_gax_go_folder into out/gax-go (no destination repository)
    dry-run   copybara migrate import_gax_go --dry-run against internal-otel-contrib/
    migrate   copybara migrate import_gax_go into internal-otel-contrib/ (the real import)
    pin       set gax_ref to -Ref with evolvectl copybara pin, and show the diff

.EXAMPLE
  ./scripts/gax-import.ps1 check
  ./scripts/gax-import.ps1 preview
  ./scripts/gax-import.ps1 pin -Ref v2.24.0
  ./scripts/gax-import.ps1 dry-run -First
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('check', 'setup', 'preview', 'validate', 'folder', 'dry-run', 'migrate', 'pin', 'help')]
    [string]$Step = 'help',
    # A gax-go tag or commit for pin, or to try in preview without editing the config.
    [string]$Ref = '',
    # The first import into a destination has no previous import to continue from.
    [switch]$First
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$config = Join-Path $root 'copybara-config\copy.bara.sky'
$destDir = Join-Path $root 'internal-otel-contrib'
$destUrl = 'file:///' + ($destDir -replace '\\', '/')
$folderOut = Join-Path $root 'out\gax-go'
if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }

function Invoke-Copybara {
    param([string[]]$CopybaraArgs)
    # Bazel and Copybara log progress on stderr; success is decided by the exit code below.
    $ErrorActionPreference = 'Continue'
    if ($env:COPYBARA) {
        & $env:COPYBARA @CopybaraArgs
    } elseif (Get-Command copybara -ErrorAction SilentlyContinue) {
        & copybara @CopybaraArgs
    } elseif (Test-Path (Join-Path $root 'copybara\MODULE.bazel')) {
        Push-Location (Join-Path $root 'copybara')
        try { & bazelisk run //java/com/google/copybara:copybara -- @CopybaraArgs } finally { Pop-Location }
    } else {
        throw 'Copybara not found. Put copybara on PATH, set $env:COPYBARA, or run: git submodule update --init copybara'
    }
    if ($LASTEXITCODE -ne 0) { throw "copybara exited with $LASTEXITCODE" }
}

function Invoke-Evolvectl {
    param([string[]]$EvolvectlArgs)
    if (-not (Get-Command evolvectl -ErrorAction SilentlyContinue)) {
        throw 'evolvectl not found. In your evolvectl checkout run: go install ./cmd/evolvectl'
    }
    $ErrorActionPreference = 'Continue'
    & evolvectl @EvolvectlArgs
    # 6 means "look at the warnings above", not a failure.
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 6) { throw "evolvectl exited with $LASTEXITCODE" }
}

function Require-Destination {
    if (-not (Test-Path (Join-Path $destDir 'HEAD'))) {
        throw "No destination repository at $destDir. Run: ./scripts/gax-import.ps1 setup"
    }
}

switch ($Step) {
    'help' {
        Get-Help $PSCommandPath -Detailed
    }
    'check' {
        foreach ($tool in 'git', 'go', 'java', 'bazelisk', 'copybara', 'evolvectl') {
            $cmd = Get-Command $tool -ErrorAction SilentlyContinue
            $where = if ($cmd) { $cmd.Source } else { 'missing' }
            '{0,-10} {1}' -f $tool, $where
        }
        '{0,-10} {1}' -f 'config', $config
        '{0,-10} {1}' -f 'dest', $(if (Test-Path (Join-Path $destDir 'HEAD')) { $destUrl } else { "$destUrl (not created; run setup)" })
    }
    'setup' {
        if (Test-Path (Join-Path $destDir 'HEAD')) {
            "Destination already exists: $destDir"
        } else {
            $ErrorActionPreference = 'Continue'
            git init --bare -q -b main $destDir
            if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
            "Created bare destination repository $destDir"
            'Its main branch is empty; pass -First on the first dry-run or migrate.'
        }
    }
    'preview' {
        $pa = @('copybara', 'preview', '--config', $config, '--workflow', 'import_gax_go', '--workspace', $root)
        if ($Ref) { $pa += @('--ref', $Ref) }
        Invoke-Evolvectl $pa
    }
    'validate' {
        Invoke-Copybara @('validate', $config)
    }
    'folder' {
        Invoke-Copybara @('migrate', $config, 'import_gax_go_folder', '--folder-dir', $folderOut)
        "Imported into $folderOut\third_party\gax-go\v2"
    }
    'dry-run' {
        Require-Destination
        $a = @('migrate', $config, 'import_gax_go', '--git-destination-url', $destUrl, '--dry-run')
        if ($First) { $a += '--force' }
        Invoke-Copybara $a
    }
    'migrate' {
        Require-Destination
        $a = @('migrate', $config, 'import_gax_go', '--git-destination-url', $destUrl)
        if ($First) { $a += '--force' }
        Invoke-Copybara $a
        "Pushed to $destUrl. Look at it with: git clone $destUrl $root\out\internal-otel-contrib"
    }
    'pin' {
        if (-not $Ref) { throw 'pin needs -Ref, for example: ./scripts/gax-import.ps1 pin -Ref v2.24.0' }
        # Both gax workflows read the gax_ref variable, so one pin updates both.
        Invoke-Evolvectl @('copybara', 'pin', '--config', $config, '--workflow', 'import_gax_go', '--ref', $Ref, '--workspace', $root)
    }
}
