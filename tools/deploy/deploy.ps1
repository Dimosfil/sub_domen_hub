[CmdletBinding()]
param(
    [string]$ConfigPath,
    [ValidateSet("auto", "sftp", "ftp")]
    [string]$Protocol = "auto",
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

function Add-OptionalParam {
    param(
        [hashtable]$Parameters,
        [string]$Name,
        [string]$Value
    )
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Parameters[$Name] = $Value
    }
}

function Resolve-DeployConfig {
    param([string]$Protocol, [string]$ConfigPath)

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        return [pscustomobject]@{
            Path = [System.IO.Path]::GetFullPath($ConfigPath)
            Protocol = if ($Protocol -ne "auto") { $Protocol } else { "" }
        }
    }

    $sftpConfig = Join-Path $PSScriptRoot "sftp.local.json"
    $ftpConfig = Join-Path $PSScriptRoot "ftp.local.json"

    if ($Protocol -eq "sftp") {
        return [pscustomobject]@{ Path = $sftpConfig; Protocol = "sftp" }
    }
    if ($Protocol -eq "ftp") {
        return [pscustomobject]@{ Path = $ftpConfig; Protocol = "ftp" }
    }
    if (Test-Path -LiteralPath $sftpConfig) {
        return [pscustomobject]@{ Path = $sftpConfig; Protocol = "sftp" }
    }
    if (Test-Path -LiteralPath $ftpConfig) {
        return [pscustomobject]@{ Path = $ftpConfig; Protocol = "ftp" }
    }

    throw "No deploy config found. Create tools/deploy/sftp.local.json or tools/deploy/ftp.local.json."
}

$selection = Resolve-DeployConfig -Protocol $Protocol -ConfigPath $ConfigPath
if (-not (Test-Path -LiteralPath $selection.Path)) {
    throw "Deploy config not found: $($selection.Path)."
}

$selectedProtocol = $selection.Protocol
if ([string]::IsNullOrWhiteSpace($selectedProtocol)) {
    $config = Get-Content -LiteralPath $selection.Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $selectedProtocol = $config.target.protocol
}
if ([string]::IsNullOrWhiteSpace($selectedProtocol)) {
    $selectedProtocol = "ftp"
}
$selectedProtocol = $selectedProtocol.ToLowerInvariant()

$backendParams = @{}
Add-OptionalParam -Parameters $backendParams -Name "ConfigPath" -Value $selection.Path
Add-OptionalParam -Parameters $backendParams -Name "SourcePath" -Value $SourcePath
Add-OptionalParam -Parameters $backendParams -Name "GitUrl" -Value $GitUrl
Add-OptionalParam -Parameters $backendParams -Name "Ref" -Value $Ref
Add-OptionalParam -Parameters $backendParams -Name "BuildCommand" -Value $BuildCommand
Add-OptionalParam -Parameters $backendParams -Name "OutputPath" -Value $OutputPath
Add-OptionalParam -Parameters $backendParams -Name "Project" -Value $Project
Add-OptionalParam -Parameters $backendParams -Name "DeployMode" -Value $DeployMode
Add-OptionalParam -Parameters $backendParams -Name "RemotePath" -Value $RemotePath
if ($SkipBuild) { $backendParams["SkipBuild"] = $true }
if ($DryRun) { $backendParams["DryRun"] = $true }

if ($selectedProtocol -eq "sftp") {
    & (Join-Path $PSScriptRoot "deploy-sftp.ps1") @backendParams
}
elseif ($selectedProtocol -in @("ftp", "ftps")) {
    & (Join-Path $PSScriptRoot "deploy-ftp.ps1") @backendParams
}
else {
    throw "Unsupported deploy protocol '$selectedProtocol'."
}
