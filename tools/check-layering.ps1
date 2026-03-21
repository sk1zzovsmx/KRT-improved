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
$rgCmd = Get-Command rg -ErrorAction SilentlyContinue
$useRipgrep = ($null -ne $rgCmd)

if (-not $useRipgrep) {
    Write-Host "rg not found in PATH; falling back to Select-String." -ForegroundColor Yellow
}

function Add-RgCheck {
    param(
        [string]$Name,
        [string]$Pattern,
        [string]$Path,
        [string[]]$ExtraArgs = @()
    )

    $matches = @(Get-KrtPatternMatches -RepoRoot $repoRoot -Pattern $Pattern -Path $Path -ExtraArgs $ExtraArgs)
    if ($matches.Count -eq 0) {
        return
    }

    $violations.Add("[$Name]")
    foreach ($line in $matches) {
        $violations.Add("  $line")
    }
}

function Add-RgRequireMatch {
    param(
        [string]$Name,
        [string]$Pattern,
        [string]$Path,
        [string[]]$ExtraArgs = @()
    )

    $matches = @(Get-KrtPatternMatches -RepoRoot $repoRoot -Pattern $Pattern -Path $Path -ExtraArgs $ExtraArgs)
    if ($matches.Count -gt 0) {
        return
    }

    $violations.Add("[$Name]")
    $violations.Add("  Missing required match for pattern '$Pattern' in '$Path'")
}

function Add-ControllerOwnershipCheck {
    param(
        [string]$FilePath,
        [string]$Owner
    )

    if (-not (Test-Path $FilePath)) {
        return
    }

    $parentViolations = New-Object System.Collections.Generic.List[string]
    $frameViolations = New-Object System.Collections.Generic.List[string]
    $lineNo = 0

    foreach ($line in Get-Content $FilePath) {
        $lineNo = $lineNo + 1

        $parentMatches = [regex]::Matches($line, 'addon\.(Changes|Master|Warnings|Logger|Spammer)\b')
        foreach ($match in $parentMatches) {
            $parentName = $match.Groups[1].Value
            if ($parentName -ne $Owner) {
                $parentViolations.Add(("{0}:{1}: {2}" -f $FilePath, $lineNo, $line.Trim()))
            }
        }

        $frameMatches = [regex]::Matches($line, 'KRT(Changes|Master|Warnings|Logger|Spammer)\b')
        foreach ($match in $frameMatches) {
            $frameOwner = $match.Groups[1].Value
            if ($frameOwner -ne $Owner) {
                $frameViolations.Add(("{0}:{1}: {2}" -f $FilePath, $lineNo, $line.Trim()))
            }
        }
    }

    if ($parentViolations.Count -gt 0) {
        $violations.Add("[Controller cross-parent refs] $FilePath (owner=$Owner)")
        foreach ($entry in $parentViolations) {
            $violations.Add("  $entry")
        }
    }

    if ($frameViolations.Count -gt 0) {
        $violations.Add("[Controller cross-parent frame refs] $FilePath (owner=$Owner)")
        foreach ($entry in $frameViolations) {
            $violations.Add("  $entry")
        }
    }
}

Add-RgCheck `
    -Name "Service direct parent refs" `
    -Pattern 'addon\.(Changes|Master|Warnings|Logger|Spammer)\b' `
    -Path "!KRT/Services" `
    -ExtraArgs @("--glob", "*.lua")

Add-RgCheck `
    -Name "Service parent frame refs" `
    -Pattern 'addon\.(Master|Logger)\.frame|KRT(Master|Logger|Warnings|Changes|Spammer)' `
    -Path "!KRT/Services" `
    -ExtraArgs @("--glob", "*.lua")

Add-RgCheck `
    -Name "Service hooksecurefunc parent refs" `
    -Pattern 'hooksecurefunc\(addon\.(Master|Logger|Warnings|Changes|Spammer)' `
    -Path "!KRT/Services" `
    -ExtraArgs @("--glob", "*.lua")

Add-RgCheck `
    -Name "Service direct UI frame APIs" `
    -Pattern 'CreateFrame|SetScript|:Show\(|:Hide\(' `
    -Path "!KRT/Services" `
    -ExtraArgs @("--glob", "*.lua")

Add-RgCheck `
    -Name "Service tooltip probe API refs" `
    -Pattern 'GameTooltip|CreateFrame\(|Set(Bag|Inventory|Loot)Item|SetHyperlink' `
    -Path "!KRT/Services" `
    -ExtraArgs @("--glob", "*.lua")

Add-RgCheck `
    -Name "Item tooltip hack leakage outside module" `
    -Pattern 'KRT_ItemTooltip|Set(Bag|Inventory|Loot)Item' `
    -Path "!KRT" `
    -ExtraArgs @("--glob", "*.lua", "--glob", "!**/Modules/Item.lua")

Add-RgRequireMatch `
    -Name "Item module tooltip implementation missing" `
    -Pattern 'KRT_ItemTooltip|GameTooltipTemplate|SetBagItem|SetHyperlink' `
    -Path "!KRT/Modules/Item.lua"

Add-RgCheck `
    -Name "Core parent frame leak" `
    -Pattern 'addon\.Master\.frame|KRTMaster' `
    -Path "!KRT/Init.lua"

Add-RgCheck `
    -Name "Core.GetFeatureShared outside Init.lua" `
    -Pattern 'function\s+Core\.(GetFeatureShared|getFeatureShared)' `
    -Path "!KRT" `
    -ExtraArgs @("--glob", "*.lua", "--glob", "!**/Init.lua")

Add-RgCheck `
    -Name "Core.EnsureLootRuntimeState outside Init.lua" `
    -Pattern 'function\s+Core\.(EnsureLootRuntimeState|ensureLootRuntimeState)' `
    -Path "!KRT" `
    -ExtraArgs @("--glob", "*.lua", "--glob", "!**/Init.lua")

Add-RgCheck `
    -Name "Reserves formatter duplicate in widget" `
    -Pattern 'local\s+function\s+FormatReserve(ItemIdLabel|ItemFallback|DroppedBy)' `
    -Path "!KRT/Widgets/ReservesUI.lua"

Add-RgCheck `
    -Name "EntryPoint duplicated controller getters" `
    -Pattern 'local\s+function\s+get(Master|Logger|Warnings|Changes|Spammer)Controller' `
    -Path "!KRT/EntryPoints" `
    -ExtraArgs @("--glob", "*.lua")

Add-RgCheck `
    -Name "Legacy parent alias usage (addon.Parent)" `
    -Pattern '\baddon\.(Master|Logger|Warnings|Changes|Spammer)\b' `
    -Path "!KRT" `
    -ExtraArgs @("--glob", "*.lua", "--glob", "!**/Init.lua")

Add-RgCheck `
    -Name "UI back-edge: Frames -> Utils" `
    -Pattern '\b(addon\.Utils|Utils\.)' `
    -Path "!KRT/Modules/UI/Frames.lua"

Add-RgCheck `
    -Name "UI back-edge: ListController -> Utils" `
    -Pattern '\b(addon\.Utils|Utils\.)' `
    -Path "!KRT/Modules/UI/ListController.lua"

Add-ControllerOwnershipCheck -FilePath "!KRT/Controllers/Changes.lua" -Owner "Changes"
Add-ControllerOwnershipCheck -FilePath "!KRT/Controllers/Master.lua" -Owner "Master"
Add-ControllerOwnershipCheck -FilePath "!KRT/Controllers/Warnings.lua" -Owner "Warnings"
Add-ControllerOwnershipCheck -FilePath "!KRT/Controllers/Logger.lua" -Owner "Logger"
Add-ControllerOwnershipCheck -FilePath "!KRT/Controllers/Spammer.lua" -Owner "Spammer"

if ($violations.Count -gt 0) {
    Write-Host "Layering check failed." -ForegroundColor Red
    foreach ($line in $violations) {
        Write-Host $line
    }
    exit 1
}

Write-Host "Layering check passed." -ForegroundColor Green
Write-Host "Checked:"
Write-Host "  Services -> Parents/frame refs"
Write-Host "  Services -> hooksecurefunc(addon.Parent, ...)"
Write-Host "  Services -> direct UI APIs"
Write-Host "  Services -> tooltip probe APIs (GameTooltip/CreateFrame/Set*Item/SetHyperlink)"
Write-Host "  Item tooltip-hack confinement (Modules/Item.lua)"
Write-Host "  Init.lua -> parent frame refs"
Write-Host "  Quick-win duplicate regressions (Core/Reserves/EntryPoints)"
Write-Host "  Legacy parent alias usage (addon.Parent) outside Init"
Write-Host "  UI module back-edges (Frames/ListController -> Utils)"
Write-Host "  Controllers -> own parent only (addon.Parent and KRTParent* ownership)"
