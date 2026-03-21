param(
    [ValidateSet(
        "EnvStatus",
        "ToolsStatus",
        "AddonValidate",
        "DocsStale",
        "AddonDeadcode",
        "AddonLint",
        "AddonFormat",
        "AddonSecurity",
        "AddonComplexity",
        "AddonDeprecations",
        "AddonOutput"
    )]
    [string]$Action = "AddonValidate",
    [string]$MechanicExe,
    [string]$AddonName = "!KRT",
    [string]$AddonPath,
    [switch]$Json,
    [switch]$AgentMode,
    [switch]$IncludeSuspicious,
    [switch]$FormatCheck,
    [string]$Categories,
    [string]$MinSeverity = "warning"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Json -and $AgentMode) {
    throw "Use either -Json or -AgentMode, not both."
}

if ([string]::IsNullOrWhiteSpace($MechanicExe)) {
    if (-not [string]::IsNullOrWhiteSpace($env:KRT_MECHANIC_EXE)) {
        $MechanicExe = $env:KRT_MECHANIC_EXE
    } else {
        $MechanicExe = "C:\dev\Mechanic\desktop\.venv\Scripts\mech.exe"
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ([string]::IsNullOrWhiteSpace($AddonPath)) {
    $AddonPath = Join-Path $repoRoot.Path "!KRT"
}

$mechanicExeFullPath = [System.IO.Path]::GetFullPath($MechanicExe)
if (-not (Test-Path -LiteralPath $mechanicExeFullPath -PathType Leaf)) {
    throw "Mechanic executable not found: $mechanicExeFullPath"
}

$addonPathFull = [System.IO.Path]::GetFullPath($AddonPath)
$actionToCommand = @{
    EnvStatus = "env.status"
    ToolsStatus = "tools.status"
    AddonValidate = "addon.validate"
    DocsStale = "docs.stale"
    AddonDeadcode = "addon.deadcode"
    AddonLint = "addon.lint"
    AddonFormat = "addon.format"
    AddonSecurity = "addon.security"
    AddonComplexity = "addon.complexity"
    AddonDeprecations = "addon.deprecations"
    AddonOutput = "addon.output"
}

$commandName = [string]$actionToCommand[$Action]
$payload = $null

switch ($Action) {
    "EnvStatus" {
        $payload = @{}
    }
    "ToolsStatus" {
        $payload = @{}
    }
    "AddonOutput" {
        $payload = @{
            agent_mode = $AgentMode.IsPresent
        }
    }
    default {
        if (-not (Test-Path -LiteralPath $addonPathFull -PathType Container)) {
            throw "Addon path does not exist: $addonPathFull"
        }

        $payload = @{
            addon = $AddonName
            path = $addonPathFull
        }

        if ($Action -eq "AddonDeadcode" -or $Action -eq "AddonSecurity" -or $Action -eq "DocsStale") {
            $payload["include_suspicious"] = $IncludeSuspicious.IsPresent
        }

        if ($Action -eq "AddonFormat") {
            $payload["check"] = $FormatCheck.IsPresent
        }

        if (($Action -eq "AddonDeadcode" -or $Action -eq "AddonSecurity" -or $Action -eq "AddonComplexity") -and
            -not [string]::IsNullOrWhiteSpace($Categories)) {
            $payload["categories"] = $Categories
        }

        if ($Action -eq "AddonDeprecations") {
            $payload["min_severity"] = $MinSeverity
        }
    }
}

if ($null -ne $payload) {
    $payloadJson = $payload | ConvertTo-Json -Depth 8 -Compress
} else {
    $payloadJson = ""
}

$venvPython = Join-Path (Split-Path -Path $mechanicExeFullPath -Parent) "python.exe"
if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        throw "python executable not found for subprocess wrapper."
    }
    $venvPython = $pythonCmd.Source
}

$prevMechExec = $env:MECH_EXEC
$prevMechCommand = $env:MECH_COMMAND
$prevMechPayload = $env:MECH_PAYLOAD
$prevMechJson = $env:MECH_JSON_FLAG
$prevMechAgent = $env:MECH_AGENT_FLAG
$prevPythonUtf8 = $env:PYTHONUTF8

$env:MECH_EXEC = $mechanicExeFullPath
$env:MECH_COMMAND = $commandName
$env:MECH_PAYLOAD = $payloadJson
$env:MECH_JSON_FLAG = if ($Json) { "1" } else { "0" }
$env:MECH_AGENT_FLAG = if ($AgentMode) { "1" } else { "0" }
$env:PYTHONUTF8 = "1"

try {
    @'
import os
import subprocess
import sys

cmd = [os.environ["MECH_EXEC"]]
if os.environ.get("MECH_JSON_FLAG") == "1":
    cmd.append("--json")
elif os.environ.get("MECH_AGENT_FLAG") == "1":
    cmd.append("--agent")

cmd.extend(["call", os.environ["MECH_COMMAND"]])
payload = os.environ.get("MECH_PAYLOAD", "")
if payload:
    cmd.append(payload)

result = subprocess.run(cmd)
sys.exit(result.returncode)
'@ | & $venvPython -

    exit $LASTEXITCODE
} finally {
    $env:MECH_EXEC = $prevMechExec
    $env:MECH_COMMAND = $prevMechCommand
    $env:MECH_PAYLOAD = $prevMechPayload
    $env:MECH_JSON_FLAG = $prevMechJson
    $env:MECH_AGENT_FLAG = $prevMechAgent
    $env:PYTHONUTF8 = $prevPythonUtf8
}
