[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Project,
    [string]$HostName,
    [string]$ProjectMapPath = (Join-Path $PSScriptRoot "hosting-projects.json"),
    [string]$PanelUrl = "https://server15.hosting.reg.ru:1500/ispmgr",
    [string]$PanelUserEnv = "SUB_DOMEN_HUB_PANEL_USER",
    [string]$PanelPasswordEnv = "SUB_DOMEN_HUB_PANEL_PASSWORD",
    [string]$AdminEmail = "webmaster@server15.hosting.reg.ru",
    [string]$IPv4 = "31.31.198.142",
    [string]$IPv6 = "2a00:f940:2:2:1:1:0:15",
    [switch]$SkipDns,
    [switch]$SkipLetsEncrypt,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RequiredEnv {
    param(
        [string]$Name,
        [string]$Label
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required environment variable is missing: $Name ($Label)."
    }
    return $value
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

function Read-ProjectTarget {
    param(
        [string]$Path,
        [string]$Project,
        [string]$HostName
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Project map not found: $Path."
    }

    $map = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace($HostName)) {
        return [pscustomobject]@{
            HostName = $HostName
            RootPath = "/www/$HostName"
        }
    }

    if ([string]::IsNullOrWhiteSpace($Project)) {
        throw "Project or HostName is required."
    }

    $entry = @($map.projects) | Where-Object { $_.id -eq $Project } | Select-Object -First 1
    if ($null -eq $entry) {
        throw "Unknown project '$Project'."
    }

    $subdomain = Get-OptionalProperty -Object $entry -Name "subdomain"
    $subdomainPath = Get-OptionalProperty -Object $entry -Name "subdomainPath"
    if ([string]::IsNullOrWhiteSpace($subdomain) -or [string]::IsNullOrWhiteSpace($subdomainPath)) {
        $status = Get-OptionalProperty -Object $entry -Name "status"
        throw "Project '$Project' is not configured for subdomain provisioning. Status: $status."
    }

    return [pscustomobject]@{
        HostName = $subdomain
        RootPath = $subdomainPath
    }
}

function Invoke-Ispmanager {
    param(
        [string]$PanelUrl,
        [string]$User,
        [string]$Password,
        [hashtable]$Query
    )

    $queryPairs = New-Object System.Collections.Generic.List[string]
    $authInfo = [Uri]::EscapeDataString($User + ":" + $Password)
    $queryPairs.Add("authinfo=$authInfo")
    foreach ($key in $Query.Keys) {
        $queryPairs.Add(([Uri]::EscapeDataString($key) + "=" + [Uri]::EscapeDataString([string]$Query[$key])))
    }

    $uri = $PanelUrl + "?" + ($queryPairs -join "&")
    return Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60
}

function Test-PanelError {
    param([object]$Response)

    $errorProperty = $Response.doc.PSObject.Properties["error"]
    if ($null -ne $errorProperty) {
        $errorValue = $errorProperty.Value
        $message = $errorValue.msg.'$'
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = ($errorValue | ConvertTo-Json -Depth 8 -Compress)
        }
        throw $message
    }
}

function Invoke-LetsEncryptIssue {
    param(
        [string]$PanelUrl,
        [string]$User,
        [string]$Password,
        [string]$HostName,
        [string]$Email
    )

    return Invoke-Ispmanager -PanelUrl $PanelUrl -User $User -Password $Password -Query @{
        func = "letsencrypt.generate"
        sok = "ok"
        enable_cert = "on"
        enable_cert_email = "off"
        wildcard = "off"
        dns_check = "off"
        domain_name = $HostName
        crtname = "$($HostName)_le"
        domain = "$HostName www.$HostName"
        email = $Email
        web_email = $Email
        keylen = "2048"
        domain_type = "web"
        from_webdomain = ""
        from_emaildomain = ""
        out = "json"
    }
}

$target = Read-ProjectTarget -Path $ProjectMapPath -Project $Project -HostName $HostName
$panelUser = $null
$panelPassword = $null
if (-not $DryRun) {
    $panelUser = Get-RequiredEnv -Name $PanelUserEnv -Label "ISPmanager user"
    $panelPassword = Get-RequiredEnv -Name $PanelPasswordEnv -Label "ISPmanager password"
}

$webdomainQuery = @{
    func = "webdomain.edit"
    sok = "ok"
    name = $target.HostName
    aliases = "www.$($target.HostName)"
    email = $AdminEmail
    home = $target.RootPath
    dirindex = "index.php index.html"
    ipsrc = "auto"
    ipaddrs = $IPv4
    php = "on"
    php_mode = "php_mode_fcgi_apache"
    secure = "on"
    out = "json"
}

$dnsQueries = @(
    @{
        func = "domain.record.edit"
        sok = "ok"
        plid = "unity-constructor.site"
        name = $target.HostName
        rtype = "A"
        ip = $IPv4
        ttl = "3600"
        out = "json"
    },
    @{
        func = "domain.record.edit"
        sok = "ok"
        plid = "unity-constructor.site"
        name = $target.HostName
        rtype = "AAAA"
        ip = $IPv6
        ttl = "3600"
        out = "json"
    }
)

Write-Host "Subdomain: $($target.HostName)"
Write-Host "Document root: $($target.RootPath)"

if ($DryRun) {
    Write-Host "[dry-run] create webdomain $($target.HostName)"
    if (-not $SkipDns) {
        Write-Host "[dry-run] create DNS A/AAAA records"
    }
    if (-not $SkipLetsEncrypt) {
        Write-Host "[dry-run] issue Let's Encrypt certificate"
    }
    return
}

if ($PSCmdlet.ShouldProcess($target.HostName, "Create ISPmanager webdomain")) {
    $webdomainResponse = Invoke-Ispmanager -PanelUrl $PanelUrl -User $panelUser -Password $panelPassword -Query $webdomainQuery
    Test-PanelError -Response $webdomainResponse
    Write-Host "Webdomain create request completed."
}

if (-not $SkipDns -and $PSCmdlet.ShouldProcess($target.HostName, "Create DNS records")) {
    foreach ($query in $dnsQueries) {
        $dnsResponse = Invoke-Ispmanager -PanelUrl $PanelUrl -User $panelUser -Password $panelPassword -Query $query
        Test-PanelError -Response $dnsResponse
    }
    Write-Host "DNS record create requests completed."
}

if (-not $SkipLetsEncrypt -and $PSCmdlet.ShouldProcess($target.HostName, "Issue Let's Encrypt certificate")) {
    $letsEncryptResponse = Invoke-LetsEncryptIssue -PanelUrl $PanelUrl -User $panelUser -Password $panelPassword -HostName $target.HostName -Email $AdminEmail
    Test-PanelError -Response $letsEncryptResponse
    Write-Host "Let's Encrypt issue request completed."
}
