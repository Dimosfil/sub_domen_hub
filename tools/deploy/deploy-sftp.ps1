[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "sftp.local.json"),
    [string]$SourcePath,
    [string]$GitUrl,
    [string]$Ref,
    [string]$BuildCommand,
    [string]$OutputPath,
    [string]$Project,
    [ValidateSet("legacy", "subdomain")]
    [string]$DeployMode,
    [string]$RemotePath,
    [switch]$SkipBuild,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$argsList = @("--config", $ConfigPath)
if (-not [string]::IsNullOrWhiteSpace($SourcePath)) { $argsList += @("--source", $SourcePath) }
if (-not [string]::IsNullOrWhiteSpace($GitUrl)) { $argsList += @("--git-url", $GitUrl) }
if (-not [string]::IsNullOrWhiteSpace($Ref)) { $argsList += @("--ref", $Ref) }
if (-not [string]::IsNullOrWhiteSpace($BuildCommand)) { $argsList += @("--build-command", $BuildCommand) }
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $argsList += @("--output-path", $OutputPath) }
if (-not [string]::IsNullOrWhiteSpace($Project)) { $argsList += @("--project", $Project) }
if (-not [string]::IsNullOrWhiteSpace($DeployMode)) { $argsList += @("--deploy-mode", $DeployMode) }
if (-not [string]::IsNullOrWhiteSpace($RemotePath)) { $argsList += @("--remote-path", $RemotePath) }
if ($SkipBuild) { $argsList += "--skip-build" }
if ($DryRun) { $argsList += "--dry-run" }

& python (Join-Path $PSScriptRoot "deploy-sftp.py") @argsList
if ($LASTEXITCODE -ne 0) {
    throw "SFTP deploy failed with exit code $LASTEXITCODE."
}
