[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "ftp.local.json"),
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

function Read-DeployConfig {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        $examplePath = Join-Path $PSScriptRoot "ftp.local.example.json"
        throw "Deploy config not found: $Path. Copy $examplePath to ftp.local.json or pass -ConfigPath."
    }

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-OptionalProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-ConfigValue {
    param(
        [object]$Object,
        [string]$Name,
        [string]$EnvNameProperty,
        [string]$Label,
        [switch]$Required
    )

    $envName = Get-OptionalProperty -Object $Object -Name $EnvNameProperty
    if (-not [string]::IsNullOrWhiteSpace($envName)) {
        $value = [Environment]::GetEnvironmentVariable($envName, "Process")
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = [Environment]::GetEnvironmentVariable($envName, "User")
        }
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = [Environment]::GetEnvironmentVariable($envName, "Machine")
        }
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    $directValue = Get-OptionalProperty -Object $Object -Name $Name
    if (-not [string]::IsNullOrWhiteSpace($directValue)) {
        return $directValue
    }

    if ($Required) {
        if (-not [string]::IsNullOrWhiteSpace($envName)) {
            throw "Required environment variable is missing or empty: $envName ($Label)."
        }

        throw "Required deploy value is missing: $Label."
    }

    return $null
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath).TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
    $targetFull = [System.IO.Path]::GetFullPath($FullPath)
    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    return [Uri]::UnescapeDataString($relativeUri.ToString()).Replace("/", [System.IO.Path]::DirectorySeparatorChar)
}

function Resolve-FullPath {
    param(
        [string]$Path,
        [string]$BasePath
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Read-ProjectMap {
    param(
        [object]$Config,
        [string]$ConfigPath
    )

    $mapPath = Get-OptionalProperty -Object $Config -Name "projectMapPath"
    if ([string]::IsNullOrWhiteSpace($mapPath)) {
        $mapPath = "hosting-projects.json"
    }

    if (-not [System.IO.Path]::IsPathRooted($mapPath)) {
        $configDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($ConfigPath))
        $mapPath = Join-Path $configDirectory $mapPath
    }

    if (-not (Test-Path -LiteralPath $mapPath)) {
        throw "Project map not found: $mapPath."
    }

    return Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Resolve-ProjectRemotePath {
    param(
        [object]$Config,
        [string]$ConfigPath,
        [string]$Project,
        [string]$DeployMode
    )

    if ([string]::IsNullOrWhiteSpace($Project)) {
        return $null
    }

    $projectMap = Read-ProjectMap -Config $Config -ConfigPath $ConfigPath
    if ([string]::IsNullOrWhiteSpace($DeployMode)) {
        $DeployMode = Get-OptionalProperty -Object $Config -Name "deployMode"
    }
    if ([string]::IsNullOrWhiteSpace($DeployMode)) {
        $DeployMode = Get-OptionalProperty -Object $projectMap -Name "defaultMode"
    }
    if ([string]::IsNullOrWhiteSpace($DeployMode)) {
        $DeployMode = "legacy"
    }

    $projectEntry = @($projectMap.projects) | Where-Object { $_.id -eq $Project } | Select-Object -First 1
    if ($null -eq $projectEntry) {
        $knownProjects = (@($projectMap.projects) | ForEach-Object { $_.id }) -join ", "
        throw "Unknown deploy project '$Project'. Known projects: $knownProjects."
    }

    if ($DeployMode -eq "legacy") {
        $path = Get-OptionalProperty -Object $projectEntry -Name "legacyPath"
    }
    else {
        $path = Get-OptionalProperty -Object $projectEntry -Name "subdomainPath"
    }

    if ([string]::IsNullOrWhiteSpace($path)) {
        $status = Get-OptionalProperty -Object $projectEntry -Name "status"
        throw "Project '$Project' has no '$DeployMode' deploy path. Status: $status."
    }

    return $path
}

function Invoke-CheckedCommand {
    param(
        [string]$Command,
        [string]$WorkingDirectory
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return
    }

    Write-Host "Running build command in $WorkingDirectory"
    Push-Location -LiteralPath $WorkingDirectory
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -Command $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Build command failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function New-SourceWorkspace {
    param(
        [string]$SourcePath,
        [string]$GitUrl,
        [string]$Ref
    )

    if (-not [string]::IsNullOrWhiteSpace($GitUrl)) {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sub-domen-hub-deploy-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

        Write-Host "Cloning source repository into $tempRoot"
        if ([string]::IsNullOrWhiteSpace($Ref)) {
            & git clone --depth 1 $GitUrl $tempRoot
        }
        else {
            & git clone --depth 1 --branch $Ref $GitUrl $tempRoot
            if ($LASTEXITCODE -ne 0) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
                $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sub-domen-hub-deploy-" + [Guid]::NewGuid().ToString("N"))
                New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
                & git clone $GitUrl $tempRoot
                if ($LASTEXITCODE -eq 0) {
                    Push-Location -LiteralPath $tempRoot
                    try {
                        & git checkout $Ref
                    }
                    finally {
                        Pop-Location
                    }
                }
            }
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Git clone/checkout failed with exit code $LASTEXITCODE."
        }

        return [pscustomobject]@{
            Path = $tempRoot
            Temporary = $true
        }
    }

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        throw "Source path or Git URL is required."
    }

    $resolvedPath = Resolve-Path -LiteralPath $SourcePath
    return [pscustomobject]@{
        Path = $resolvedPath.ProviderPath
        Temporary = $false
    }
}

function Test-ExcludedPath {
    param(
        [string]$RelativePath,
        [string[]]$ExcludePatterns
    )

    $normalized = $RelativePath.Replace("\", "/")
    foreach ($pattern in $ExcludePatterns) {
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }

        $wildcard = $pattern.Replace("\", "/").Replace("**", "*")
        if ($normalized -like $wildcard) {
            return $true
        }

        if ($normalized -like ($wildcard.TrimEnd("/") + "/*")) {
            return $true
        }
    }

    return $false
}

function Get-UploadFiles {
    param(
        [string]$Root,
        [string[]]$ExcludePatterns
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force | ForEach-Object {
        $relative = Get-RelativePath -BasePath $rootFull -FullPath $_.FullName
        if (-not (Test-ExcludedPath -RelativePath $relative -ExcludePatterns $ExcludePatterns)) {
            [pscustomobject]@{
                FullName = $_.FullName
                RelativePath = $relative.Replace("\", "/")
                Length = $_.Length
            }
        }
    }
}

function Join-RemotePath {
    param(
        [string]$BasePath,
        [string]$RelativePath
    )

    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($BasePath)) {
        $parts += ($BasePath -split "[/\\]" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if (-not [string]::IsNullOrWhiteSpace($RelativePath)) {
        $parts += ($RelativePath -split "[/\\]" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return "/" + ($parts -join "/")
}

function ConvertTo-FtpUri {
    param(
        [string]$HostName,
        [string]$RemotePath
    )

    $escapedParts = $RemotePath -split "/" | Where-Object { $_ -ne "" } | ForEach-Object {
        [Uri]::EscapeDataString($_)
    }

    $escapedPath = $escapedParts -join "/"
    if ([string]::IsNullOrWhiteSpace($escapedPath)) {
        return "ftp://$HostName/"
    }

    return "ftp://$HostName/$escapedPath"
}

function Invoke-FtpRequest {
    param(
        [string]$Uri,
        [string]$Method,
        [System.Net.NetworkCredential]$Credential,
        [bool]$EnableSsl,
        [string]$UploadFile
    )

    $request = [System.Net.FtpWebRequest]::Create($Uri)
    $request.Method = $Method
    $request.Credentials = $Credential
    $request.Proxy = $null
    $request.UseBinary = $true
    $request.UsePassive = $true
    $request.EnableSsl = $EnableSsl

    if ($UploadFile) {
        $fileInfo = Get-Item -LiteralPath $UploadFile
        $request.ContentLength = $fileInfo.Length
        $buffer = New-Object byte[] 65536
        $fileStream = [System.IO.File]::OpenRead($UploadFile)
        try {
            $requestStream = $request.GetRequestStream()
            try {
                while (($read = $fileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $requestStream.Write($buffer, 0, $read)
                }
            }
            finally {
                $requestStream.Dispose()
            }
        }
        finally {
            $fileStream.Dispose()
        }
    }

    $response = $request.GetResponse()
    try {
        return $response.StatusDescription
    }
    finally {
        $response.Dispose()
    }
}

function Ensure-FtpDirectory {
    param(
        [string]$HostName,
        [string]$RemotePath,
        [System.Net.NetworkCredential]$Credential,
        [bool]$EnableSsl
    )

    $parts = $RemotePath -split "/" | Where-Object { $_ -ne "" }
    $current = ""
    foreach ($part in $parts) {
        $current = Join-RemotePath -BasePath $current -RelativePath $part
        $uri = ConvertTo-FtpUri -HostName $HostName -RemotePath $current
        try {
            Invoke-FtpRequest -Uri $uri -Method ([System.Net.WebRequestMethods+Ftp]::MakeDirectory) -Credential $Credential -EnableSsl $EnableSsl | Out-Null
        }
        catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                $_.Exception.Response.Dispose()
            }
        }
    }
}

function Send-FtpFiles {
    param(
        [string]$HostName,
        [string]$Username,
        [string]$Password,
        [string]$RemotePath,
        [object[]]$Files,
        [bool]$EnableSsl,
        [switch]$DryRun
    )

    $credential = New-Object System.Net.NetworkCredential($Username, $Password)
    $remoteDirectories = New-Object "System.Collections.Generic.HashSet[string]"
    [void]$remoteDirectories.Add((Join-RemotePath -BasePath $RemotePath -RelativePath ""))

    foreach ($file in $Files) {
        $relativeDirectory = Split-Path -Path $file.RelativePath -Parent
        $directory = Join-RemotePath -BasePath $RemotePath -RelativePath $relativeDirectory
        [void]$remoteDirectories.Add($directory)
    }

    foreach ($directory in ($remoteDirectories | Sort-Object Length)) {
        if ($DryRun) {
            Write-Host "[dry-run] ensure remote directory $directory"
        }
        else {
            Ensure-FtpDirectory -HostName $HostName -RemotePath $directory -Credential $credential -EnableSsl $EnableSsl
        }
    }

    foreach ($file in $Files) {
        $targetPath = Join-RemotePath -BasePath $RemotePath -RelativePath $file.RelativePath
        if ($DryRun) {
            Write-Host "[dry-run] upload $($file.RelativePath) -> $targetPath"
            continue
        }

        $uri = ConvertTo-FtpUri -HostName $HostName -RemotePath $targetPath
        Invoke-FtpRequest -Uri $uri -Method ([System.Net.WebRequestMethods+Ftp]::UploadFile) -Credential $credential -EnableSsl $EnableSsl -UploadFile $file.FullName | Out-Null
        Write-Host "Uploaded $($file.RelativePath)"
    }
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$config = Read-DeployConfig -Path $ConfigPath

$sourceConfig = Get-OptionalProperty -Object $config -Name "source"
$buildConfig = Get-OptionalProperty -Object $config -Name "build"
$targetConfig = Get-OptionalProperty -Object $config -Name "target"
if ($null -eq $targetConfig) {
    throw "Config section target is required."
}

$effectiveGitUrl = if (-not [string]::IsNullOrWhiteSpace($GitUrl)) { $GitUrl } else { Get-OptionalProperty -Object $sourceConfig -Name "gitUrl" }
$effectiveRef = if (-not [string]::IsNullOrWhiteSpace($Ref)) { $Ref } else { Get-OptionalProperty -Object $sourceConfig -Name "ref" }
$configuredSourcePath = Get-OptionalProperty -Object $sourceConfig -Name "path"
$effectiveSourcePath = if (-not [string]::IsNullOrWhiteSpace($SourcePath)) { $SourcePath } else { $configuredSourcePath }
if (-not [string]::IsNullOrWhiteSpace($effectiveSourcePath)) {
    $effectiveSourcePath = Resolve-FullPath -Path $effectiveSourcePath -BasePath $projectRoot
}

$protocol = Get-OptionalProperty -Object $targetConfig -Name "protocol"
if ([string]::IsNullOrWhiteSpace($protocol)) {
    $protocol = "ftp"
}
$protocol = $protocol.ToLowerInvariant()
if ($protocol -notin @("ftp", "ftps")) {
    throw "Protocol '$protocol' is not supported by this script yet. Use ftp/ftps or add a project SFTP adapter."
}

$hostName = Get-ConfigValue -Object $targetConfig -Name "host" -EnvNameProperty "hostEnv" -Label "FTP host" -Required
$username = Get-ConfigValue -Object $targetConfig -Name "username" -EnvNameProperty "usernameEnv" -Label "FTP username" -Required
$password = Get-ConfigValue -Object $targetConfig -Name "password" -EnvNameProperty "passwordEnv" -Label "FTP password" -Required
$projectRemotePath = Resolve-ProjectRemotePath -Config $config -ConfigPath $ConfigPath -Project $Project -DeployMode $DeployMode
$effectiveRemotePath = if (-not [string]::IsNullOrWhiteSpace($RemotePath)) { $RemotePath } elseif (-not [string]::IsNullOrWhiteSpace($projectRemotePath)) { $projectRemotePath } else { Get-OptionalProperty -Object $targetConfig -Name "remotePath" }
if ([string]::IsNullOrWhiteSpace($effectiveRemotePath)) {
    throw "Remote path is required. Set target.remotePath or pass -RemotePath."
}

$effectiveBuildCommand = if (-not [string]::IsNullOrWhiteSpace($BuildCommand)) { $BuildCommand } else { Get-OptionalProperty -Object $buildConfig -Name "command" }
$configuredOutputPath = Get-OptionalProperty -Object $buildConfig -Name "outputPath"
$effectiveOutputPath = if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath } elseif (-not [string]::IsNullOrWhiteSpace($configuredOutputPath)) { $configuredOutputPath } else { "." }

$excludePatterns = @()
$configuredExclude = Get-OptionalProperty -Object $config -Name "exclude"
if ($configuredExclude) {
    $excludePatterns = @($configuredExclude)
}

$workspace = $null
try {
    $workspace = New-SourceWorkspace -SourcePath $effectiveSourcePath -GitUrl $effectiveGitUrl -Ref $effectiveRef

    if (-not $SkipBuild) {
        Invoke-CheckedCommand -Command $effectiveBuildCommand -WorkingDirectory $workspace.Path
    }

    $artifactPath = Resolve-FullPath -Path $effectiveOutputPath -BasePath $workspace.Path
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Container)) {
        throw "Build output folder does not exist: $artifactPath"
    }

    $files = @(Get-UploadFiles -Root $artifactPath -ExcludePatterns $excludePatterns)
    if ($files.Count -eq 0) {
        throw "No files selected for upload from $artifactPath."
    }

    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    Write-Host "Deploy source: $($workspace.Path)"
    Write-Host "Upload root: $artifactPath"
    Write-Host "Remote path: $effectiveRemotePath"
    Write-Host "Selected files: $($files.Count), bytes: $totalBytes"

    Send-FtpFiles -HostName $hostName -Username $username -Password $password -RemotePath $effectiveRemotePath -Files $files -EnableSsl ($protocol -eq "ftps") -DryRun:$DryRun

    if ($DryRun) {
        Write-Host "Dry run completed."
    }
    else {
        Write-Host "Deploy completed."
    }
}
finally {
    if ($workspace -and $workspace.Temporary -and (Test-Path -LiteralPath $workspace.Path)) {
        Remove-Item -LiteralPath $workspace.Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}
