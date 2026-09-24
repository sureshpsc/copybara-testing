<#
.SYNOPSIS
  Copybara brings a new library version into the monorepo; evolvectl fixes the code that calls it.

.DESCRIPTION
  Everything is created under test/out, which git ignores. Delete it with the reset step.

  Steps, in order:
    check       show which tools are installed
    setup       create out/acme-retry (tags v1.0.0, v2.0.0), out/monorepo.git (bare),
                out/monorepo (your checkout), and out/copy.bara.sky (paths filled in)
    preview     evolvectl copybara preview: what each import would add to out/monorepo
    validate    copybara validate out/copy.bara.sky
    dry-run     copybara migrate --dry-run
    migrate     copybara migrate, then git pull in out/monorepo
    simulate    the same import without Copybara: copy the preview output and commit it
    build       go build and go test in out/monorepo
    break       in a scratch copy, switch go.mod and imports to the new copy by hand, without
                fixing any code, and show the compile errors (what evolvectl saves you from)
    impact      evolvectl impact: removed or changed API and every call site
    upgrade     evolvectl upgrade, then commit the result in out/monorepo
    reset       delete test/out

  -Library gax | retry | all (default all) picks the import for preview, dry-run, migrate,
  simulate, impact, and upgrade.

.EXAMPLE
  ./test/demo.ps1 setup
  ./test/demo.ps1 migrate -Library gax
  ./test/demo.ps1 impact -Library gax
  ./test/demo.ps1 upgrade -Library gax -DryRun
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('check', 'setup', 'preview', 'validate', 'dry-run', 'migrate', 'simulate', 'build', 'break', 'impact', 'upgrade', 'reset', 'help')]
    [string]$Step = 'help',
    [ValidateSet('gax', 'retry', 'all')]
    [string]$Library = 'all',
    # upgrade only: work on a temporary copy and leave out/monorepo unchanged.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$test = $PSScriptRoot
$root = Split-Path -Parent $test
$out = Join-Path $test 'out'
$config = Join-Path $out 'copy.bara.sky'
$mono = Join-Path $out 'monorepo'
$monoBare = Join-Path $out 'monorepo.git'
$retryRepo = Join-Path $out 'acme-retry'
if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }

$libs = [ordered]@{
    gax   = @{
        Workflow = 'import_gax_go'; Module = 'github.com/googleapis/gax-go'; To = 'v2.0.2'
        ToModule = 'github.com/googleapis/gax-go/v2'; Dir = 'third_party/gax-go/v2'
    }
    retry = @{
        Workflow = 'import_acme_retry'; Module = 'github.com/acme/retry'; To = 'v2.0.0'
        ToModule = 'github.com/acme/retry/v2'; Dir = 'third_party/acme-retry/v2'
    }
}
$selected = if ($Library -eq 'all') { @($libs.Keys) } else { @($Library) }

function Invoke-Native {
    param([string]$Exe, [string[]]$NativeArgs, [int[]]$Ok = @(0))
    # Native tools log progress on stderr; success is decided by the exit code.
    $ErrorActionPreference = 'Continue'
    & $Exe @NativeArgs | Out-Host
    if ($Ok -notcontains $LASTEXITCODE) { throw "$Exe $($NativeArgs -join ' ') exited with $LASTEXITCODE" }
}

function Invoke-Git {
    param([string]$Dir, [string[]]$GitArgs)
    # -c sets the identity for this command only; your git config is not changed.
    Invoke-Native git (@('-C', $Dir, '-c', 'user.name=Demo', '-c', 'user.email=demo@example.com', '-c', 'core.autocrlf=false') + $GitArgs)
}

function Invoke-Copybara {
    param([string[]]$CopybaraArgs)
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
    # 6 means finished with items to review, not a failure.
    Invoke-Native evolvectl $EvolvectlArgs @(0, 6)
}

function Require-Setup {
    if (-not (Test-Path $config)) { throw 'Run ./test/demo.ps1 setup first.' }
}

function Copy-Files {
    param([string]$From, [string]$To)
    New-Item -ItemType Directory -Force $To | Out-Null
    Get-ChildItem -Force $From | Where-Object { $_.Name -ne '.git' } | Copy-Item -Destination $To -Recurse -Force
}

switch ($Step) {
    'help' { Get-Help $PSCommandPath -Detailed }

    'check' {
        foreach ($tool in 'git', 'go', 'java', 'bazelisk', 'copybara', 'evolvectl') {
            $cmd = Get-Command $tool -ErrorAction SilentlyContinue
            '{0,-10} {1}' -f $tool, $(if ($cmd) { $cmd.Source } else { 'missing' })
        }
        '{0,-10} {1}' -f 'setup', $(if (Test-Path $config) { "done ($out)" } else { 'not yet; run setup' })
    }

    'setup' {
        if (Test-Path $out) { throw "$out already exists. Run ./test/demo.ps1 reset to start over." }
        New-Item -ItemType Directory $out | Out-Null

        # The library repository, one commit and tag per version.
        Invoke-Native git @('init', '-q', '-b', 'main', $retryRepo)
        foreach ($v in 'v1.0.0', 'v2.0.0') {
            Get-ChildItem -Force $retryRepo | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force
            Copy-Files (Join-Path $test "libs\acme-retry\$v") $retryRepo
            Invoke-Git $retryRepo @('add', '-A')
            Invoke-Git $retryRepo @('commit', '-q', '-m', "acme/retry $v")
            Invoke-Git $retryRepo @('tag', $v)
        }

        # The monorepo as it is today: services plus the old copies in third_party/.
        Invoke-Native git @('init', '-q', '-b', 'main', $mono)
        Copy-Files (Join-Path $test 'monorepo') $mono
        Invoke-Git $mono @('add', '-A')
        Invoke-Git $mono @('commit', '-q', '-m', 'Monorepo today: gax-go 2016 and acme/retry v1 in third_party')
        Invoke-Native git @('clone', '-q', '--bare', $mono, $monoBare)
        Invoke-Git $mono @('remote', 'add', 'origin', $monoBare)
        Invoke-Git $mono @('fetch', '-q', 'origin')
        Invoke-Git $mono @('branch', '-q', '-u', 'origin/main')

        $base = 'file:///' + ($test -replace '\\', '/')
        (Get-Content -Raw (Join-Path $test 'copy.bara.sky')).Replace('file:///TEST_DIR', $base) |
            Set-Content -Encoding ascii $config
        "Created in $out"
        '  acme-retry     library repository, tags v1.0.0 and v2.0.0'
        '  monorepo.git   the monorepo Copybara pushes to'
        '  monorepo       your checkout; evolvectl runs here'
        '  copy.bara.sky  the config with this machine''s paths'
    }

    'preview' {
        Require-Setup
        foreach ($k in $selected) {
            Write-Host "== $($libs[$k].Workflow)"
            Invoke-Evolvectl @('copybara', 'preview', '--config', $config, '--workflow', $libs[$k].Workflow,
                '--out', (Join-Path $out "preview\$k"), '--against', $mono, '--workspace', $out)
        }
    }

    'validate' {
        Require-Setup
        Invoke-Copybara @('validate', $config)
    }

    'dry-run' {
        Require-Setup
        foreach ($k in $selected) {
            Invoke-Copybara @('migrate', $config, $libs[$k].Workflow, '--dry-run', '--force')
        }
    }

    'migrate' {
        Require-Setup
        foreach ($k in $selected) {
            # --force: the monorepo has no earlier Copybara import of this library to continue from.
            Invoke-Copybara @('migrate', $config, $libs[$k].Workflow, '--force')
        }
        Invoke-Git $mono @('pull', '-q', '--ff-only')
        Invoke-Native git @('-C', $mono, 'log', '--oneline', '-5')
    }

    'simulate' {
        Require-Setup
        foreach ($k in $selected) {
            $lib = $libs[$k]
            $prev = Join-Path $out "preview\$k"
            Invoke-Evolvectl @('copybara', 'preview', '--config', $config, '--workflow', $lib.Workflow, '--out', $prev, '--workspace', $out)
            Copy-Files (Join-Path $prev ($lib.Dir -replace '/', '\')) (Join-Path $mono ($lib.Dir -replace '/', '\'))
            Invoke-Git $mono @('add', '-A')
            Invoke-Git $mono @('commit', '-q', '-m', "Import $($lib.ToModule) $($lib.To) into $($lib.Dir) (simulated Copybara import)")
            Write-Host "Committed $($lib.Dir) in $mono"
        }
    }

    'build' {
        Require-Setup
        Push-Location $mono
        try {
            Invoke-Native go @('build', './...') @(0, 1)
            Invoke-Native go @('test', './...') @(0, 1)
        } finally { Pop-Location }
    }

    'break' {
        Require-Setup
        $scratch = Join-Path $out 'break'
        if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
        Copy-Files $mono $scratch
        Push-Location $scratch
        try {
            foreach ($k in $selected) {
                $lib = $libs[$k]
                if (-not (Test-Path (Join-Path $scratch ($lib.Dir -replace '/', '\')))) {
                    throw "$($lib.Dir) is not in out/monorepo yet. Run migrate or simulate first."
                }
                Invoke-Native go @('mod', 'edit', "-droprequire=$($lib.Module)", "-require=$($lib.ToModule)@$($lib.To)", "-replace=$($lib.ToModule)=./$($lib.Dir)")
                Get-ChildItem -Recurse -Filter *.go (Join-Path $scratch 'services') | ForEach-Object {
                    $src = Get-Content -Raw $_.FullName
                    $new = $src.Replace('"' + $lib.Module + '"', '"' + $lib.ToModule + '"')
                    if ($new -ne $src) { [IO.File]::WriteAllText($_.FullName, $new) }
                }
            }
            Write-Host "Scratch copy ${scratch}: go.mod and imports switched, no code fixed. go build says:"
            Invoke-Native go @('mod', 'tidy') @(0, 1)
            Invoke-Native go @('build', './...') @(0, 1)
        } finally { Pop-Location }
    }

    'impact' {
        Require-Setup
        foreach ($k in $selected) {
            $lib = $libs[$k]
            Invoke-Evolvectl @('impact', $lib.Module, '--to', $lib.To, '--to-module', $lib.ToModule, '--use-dir', $lib.Dir, '--workspace', $mono)
        }
    }

    'upgrade' {
        Require-Setup
        foreach ($k in $selected) {
            $lib = $libs[$k]
            $a = @('upgrade', $lib.Module, '--to', $lib.To, '--to-module', $lib.ToModule, '--use-dir', $lib.Dir, '--workspace', $mono)
            if ($DryRun) { $a += '--dry-run' }
            Invoke-Evolvectl $a
            if (-not $DryRun) {
                Invoke-Git $mono @('add', '-A')
                Invoke-Git $mono @('commit', '-q', '-m', "Move callers to $($lib.ToModule) $($lib.To) (evolvectl upgrade)")
                Write-Host "Committed the evolvectl changes in $mono. See them with: git -C $mono show --stat"
            }
        }
    }

    'reset' {
        if (Test-Path $out) { Remove-Item -Recurse -Force $out; "Deleted $out" } else { 'Nothing to delete.' }
    }
}
