Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$violations = New-Object System.Collections.Generic.List[string]

function Invoke-Rg {
    param(
        [string]$Pattern,
        [string]$Target,
        [string[]]$ExtraArgs
    )

    $args = @("-n", $Pattern, $Target)
    if ($ExtraArgs) {
        $args = $args + $ExtraArgs
    }

    $output = & rg @args 2>$null
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        return @($output)
    }
    if ($exitCode -eq 1) {
        return @()
    }

    throw "rg failed for pattern '$Pattern' (exit $exitCode)."
}

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

Write-Host "Check 1/7: KRT_Raids access confined to DB layer..."
$krtRaidsMatches = @(Invoke-Rg `
    -Pattern "\bKRT_Raids\b" `
    -Target "!KRT" `
    -ExtraArgs @("-g", "*.lua", "-g", "!Libs/**"))

Add-MatchesOutsideAllowed `
    -Header "[KRT_Raids outside DB layer]" `
    -Lines $krtRaidsMatches `
    -AllowedPaths @("!KRT\KRT.lua", "!KRT\Core\DBRaidStore.lua")

Write-Host "Check 2/7: legacy runtime cache keys only cleaned in KRT/DBRaidStore..."
$legacyCacheMatches = @(Invoke-Rg `
    -Pattern "_playersByName|_playerIdxByNid|_bossIdxByNid|_lootIdxByNid" `
    -Target "!KRT" `
    -ExtraArgs @("-g", "*.lua", "-g", "!Libs/**"))

Add-MatchesOutsideAllowed `
    -Header "[Legacy runtime keys used outside cleanup layer]" `
    -Lines $legacyCacheMatches `
    -AllowedPaths @("!KRT\KRT.lua", "!KRT\Core\DBRaidStore.lua")

Write-Host "Check 3/7: XML stays layout-only..."
$xmlScriptMatches = @(Invoke-Rg `
    -Pattern "<Scripts>|<On[A-Za-z]+>" `
    -Target "!KRT/UI" `
    -ExtraArgs @("-g", "*.xml"))

if ($xmlScriptMatches.Count -gt 0) {
    $violations.Add("[XML inline scripts found]")
    foreach ($line in $xmlScriptMatches) {
        $violations.Add("  $line")
    }
}

Write-Host "Check 4/7: raid-store access goes through DB facade..."
$directStoreMatches = @(Invoke-Rg `
    -Pattern "addon\\.Services\\.RaidStore|services and services\\.RaidStore|addon\\.DB\\.RaidStore|db and db\\.RaidStore" `
    -Target "!KRT" `
    -ExtraArgs @("-g", "*.lua", "-g", "!Libs/**"))

Add-MatchesOutsideAllowed `
    -Header "[Direct RaidStore access outside DB layer]" `
    -Lines $directStoreMatches `
    -AllowedPaths @("!KRT\Core\DBManager.lua", "!KRT\Core\DBRaidStore.lua")

Write-Host "Check 5/7: query/migration/validator access goes through DB facade..."
$directQueryMigrationMatches = @(Invoke-Rg `
    -Pattern "addon\\.Services\\.RaidQueries|services and services\\.RaidQueries|addon\\.Services\\.RaidMigrations|services and services\\.RaidMigrations|addon\\.Services\\.RaidValidator|services and services\\.RaidValidator|addon\\.DB\\.RaidQueries|db and db\\.RaidQueries|addon\\.DB\\.RaidMigrations|db and db\\.RaidMigrations|addon\\.DB\\.RaidValidator|db and db\\.RaidValidator" `
    -Target "!KRT" `
    -ExtraArgs @("-g", "*.lua", "-g", "!Libs/**"))

Add-MatchesOutsideAllowed `
    -Header "[Direct RaidQueries/RaidMigrations/RaidValidator access outside DB layer]" `
    -Lines $directQueryMigrationMatches `
    -AllowedPaths @(
        "!KRT\Core\DBManager.lua",
        "!KRT\Core\DBManager.Mock.lua",
        "!KRT\Core\DBRaidQueries.lua",
        "!KRT\Core\DBRaidMigrations.lua",
        "!KRT\Core\DBRaidValidator.lua"
    )

Write-Host "Check 6/7: no local getRaidStore helpers remain..."
$localRaidStoreHelpers = @(Invoke-Rg `
    -Pattern "local function getRaidStore\(|local function GetRaidStore\(" `
    -Target "!KRT" `
    -ExtraArgs @("-g", "*.lua", "-g", "!Libs/**"))

if ($localRaidStoreHelpers.Count -gt 0) {
    $violations.Add("[Local getRaidStore helpers found]")
    foreach ($line in $localRaidStoreHelpers) {
        $violations.Add("  $line")
    }
}

Write-Host "Check 7/7: validator script is lint-clean..."
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

if ($violations.Count -gt 0) {
    Write-Host "Raid hardening checks failed." -ForegroundColor Red
    foreach ($line in $violations) {
        Write-Host $line
    }
    exit 1
}

Write-Host "Raid hardening checks passed." -ForegroundColor Green
Write-Host "Confirmed:"
Write-Host "  1) KRT_Raids confined to KRT.lua + Core/DBRaidStore.lua"
Write-Host "  2) Legacy runtime cache keys only in cleanup layer"
Write-Host "  3) !KRT/UI XML has no <Scripts>/<On...> blocks"
Write-Host "  4) RaidStore access routed through DB facade (except DB layer)"
Write-Host "  5) RaidQueries/RaidMigrations/RaidValidator access routed through DB facade"
Write-Host "  6) No local getRaidStore helpers in modules"
Write-Host "  7) tools/validate-raid-schema.lua passes luacheck"
