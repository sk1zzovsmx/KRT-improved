Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolingCommonPath = Join-Path $PSScriptRoot "tooling-common.ps1"
if (-not (Test-Path -LiteralPath $toolingCommonPath)) {
    $toolingCommonPath = Join-Path (Split-Path -Parent $PSScriptRoot) "tooling-common.ps1"
}
. $toolingCommonPath
$repoRoot = Enter-KrtRepoRoot -ScriptRoot $PSScriptRoot
Disable-KrtNativeCommandErrors

$violations = New-Object System.Collections.Generic.List[string]

function Normalize-PathKey {
    param([string]$Path)
    return ($Path -replace "/", "\").ToLowerInvariant()
}

function Add-MatchesOutsideAllowed {
    param(
        [string]$Header,
        [string[]]$Lines,
        [string[]]$AllowedPaths
    )

    $allowed = @{}
    foreach ($path in $AllowedPaths) {
        $allowed[(Normalize-PathKey -Path $path)] = $true
    }

    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, "^([^:]+):\d+:")
        if (-not $match.Success) {
            $bad.Add($line)
            continue
        }
        $pathKey = Normalize-PathKey -Path $match.Groups[1].Value
        if (-not $allowed.ContainsKey($pathKey)) {
            $bad.Add($line)
        }
    }

    if ($bad.Count -gt 0) {
        $violations.Add($Header)
        foreach ($line in $bad) {
            $violations.Add("  $line")
        }
    }
}

Write-Host "Check 1/8: KRT_Raids access confined to DB layer..."
$krtRaidsMatches = @(Get-KrtPatternMatches `
    -RepoRoot $repoRoot `
    -Pattern "\bKRT_Raids\b" `
    -Path "!KRT" `
    -ExtraArgs @("-g", "*.lua", "-g", "!Libs/**"))

Add-MatchesOutsideAllowed `
    -Header "[KRT_Raids outside DB layer]" `
    -Lines $krtRaidsMatches `
    -AllowedPaths @("!KRT\Init.lua", "!KRT\Core\DBRaidStore.lua")

Write-Host "Check 2/8: legacy runtime cache keys only cleaned in !KRT/Core/DBRaidStore.lua..."
$legacyCacheMatches = @(Get-KrtPatternMatches `
    -RepoRoot $repoRoot `
    -Pattern "_playersByName|_playerIdxByNid|_bossIdxByNid|_lootIdxByNid" `
    -Path "!KRT" `
    -ExtraArgs @("-g", "*.lua", "-g", "!Libs/**"))

Add-MatchesOutsideAllowed `
    -Header "[Legacy runtime keys used outside cleanup layer]" `
    -Lines $legacyCacheMatches `
    -AllowedPaths @("!KRT\Init.lua", "!KRT\Core\DBRaidStore.lua")

Write-Host "Check 3/8: XML stays layout-only..."
$xmlScriptMatches = @(Get-KrtPatternMatches `
    -RepoRoot $repoRoot `
    -Pattern "<Scripts>|<On[A-Za-z]+>" `
    -Path "!KRT/UI" `
    -ExtraArgs @("-g", "*.xml"))

if ($xmlScriptMatches.Count -gt 0) {
    $violations.Add("[XML inline scripts found]")
    foreach ($line in $xmlScriptMatches) {
        $violations.Add("  $line")
    }
}

Write-Host "Check 4/8: raid-store access goes through DB facade..."
$directStoreMatches = @(Get-KrtPatternMatches `
    -RepoRoot $repoRoot `
    -Pattern "addon\\.Services\\.RaidStore|services and services\\.RaidStore|addon\\.DB\\.RaidStore|db and db\\.RaidStore" `
    -Path "!KRT" `
    -ExtraArgs @("-g", "*.lua", "-g", "!Libs/**"))

Add-MatchesOutsideAllowed `
    -Header "[Direct RaidStore access outside DB layer]" `
    -Lines $directStoreMatches `
    -AllowedPaths @("!KRT\Core\DBManager.lua", "!KRT\Core\DBRaidStore.lua")

Write-Host "Check 5/8: query/migration/validator/syncer access goes through DB facade..."
$directQueryMigrationMatches = @(Get-KrtPatternMatches `
    -RepoRoot $repoRoot `
    -Pattern "addon\\.Services\\.RaidQueries|services and services\\.RaidQueries|addon\\.Services\\.RaidMigrations|services and services\\.RaidMigrations|addon\\.Services\\.RaidValidator|services and services\\.RaidValidator|addon\\.Services\\.Syncer|services and services\\.Syncer|addon\\.DB\\.RaidQueries|db and db\\.RaidQueries|addon\\.DB\\.RaidMigrations|db and db\\.RaidMigrations|addon\\.DB\\.RaidValidator|db and db\\.RaidValidator|addon\\.DB\\.Syncer|db and db\\.Syncer" `
    -Path "!KRT" `
    -ExtraArgs @("-g", "*.lua", "-g", "!Libs/**"))

Add-MatchesOutsideAllowed `
    -Header "[Direct RaidQueries/RaidMigrations/RaidValidator/Syncer access outside DB layer]" `
    -Lines $directQueryMigrationMatches `
    -AllowedPaths @(
        "!KRT\Core\DBManager.lua",
        "!KRT\Core\DBManager.Mock.lua",
        "!KRT\Core\DBRaidQueries.lua",
        "!KRT\Core\DBRaidMigrations.lua",
        "!KRT\Core\DBRaidValidator.lua",
        "!KRT\Core\DBSyncer.lua"
    )

Write-Host "Check 6/8: no local getRaidStore helpers remain..."
$localRaidStoreHelpers = @(Get-KrtPatternMatches `
    -RepoRoot $repoRoot `
    -Pattern "local function getRaidStore\(|local function GetRaidStore\(" `
    -Path "!KRT" `
    -ExtraArgs @("-g", "*.lua", "-g", "!Libs/**"))

if ($localRaidStoreHelpers.Count -gt 0) {
    $violations.Add("[Local getRaidStore helpers found]")
    foreach ($line in $localRaidStoreHelpers) {
        $violations.Add("  $line")
    }
}

Write-Host "Check 7/8: validator script is lint-clean..."
if (-not (Get-Command luacheck -ErrorAction SilentlyContinue)) {
    $violations.Add("[luacheck missing] Install luacheck to run validator lint check.")
} else {
    $lintOutput = & luacheck "tools/validate-raid-schema.lua" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $violations.Add("[validator luacheck failed]")
        foreach ($line in @($lintOutput)) {
            $violations.Add("  $line")
        }
    }
}

Write-Host "Check 8/8: SV round-trip fixtures are stable..."
$roundTripScript = Resolve-Path (Join-Path $repoRoot "tools/sv-roundtrip.lua")
$fixtureDir = Resolve-Path (Join-Path $repoRoot "tests/fixtures/sv")

if (-not $fixtureDir) {
    $violations.Add("[roundtrip fixtures missing] tests/fixtures/sv not found.")
} else {
    $luaRuntime = Resolve-KrtLuaRuntime
    if (-not $luaRuntime) {
        Write-Host "Warning: Lua runtime not found; skipping round-trip fixture execution." -ForegroundColor Yellow
    } else {
        $fixtureFiles = @(Get-ChildItem -LiteralPath $fixtureDir.Path -File -Filter "*.lua" | Sort-Object Name)
        if ($fixtureFiles.Count -eq 0) {
            $violations.Add("[roundtrip fixtures missing] No .lua fixture files under tests/fixtures/sv.")
        } else {
            foreach ($fixture in $fixtureFiles) {
                $output = & $luaRuntime $roundTripScript.Path $fixture.FullName 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $violations.Add("[roundtrip drift] $($fixture.FullName)")
                    foreach ($line in @($output)) {
                        $violations.Add("  $line")
                    }
                }
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "Raid hardening checks failed." -ForegroundColor Red
    foreach ($line in $violations) {
        Write-Host $line
    }
    exit 1
}

Write-Host "Raid hardening checks passed." -ForegroundColor Green
Write-Host "Confirmed:"
Write-Host "  1) KRT_Raids confined to Init.lua + Core/DBRaidStore.lua"
Write-Host "  2) Legacy runtime cache keys only in cleanup layer"
Write-Host "  3) !KRT/UI XML has no <Scripts>/<On...> blocks"
Write-Host "  4) RaidStore access routed through DB facade (except DB layer)"
Write-Host "  5) RaidQueries/RaidMigrations/RaidValidator/Syncer access routed through DB facade"
Write-Host "  6) No local getRaidStore helpers in modules"
Write-Host "  7) tools/validate-raid-schema.lua passes luacheck"
Write-Host "  8) SV round-trip fixtures (tests/fixtures/sv) no-drift check (lua/luajit required)"
