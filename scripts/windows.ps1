# WARP - Cloudflare WARP MASQUE-H2 Multi-Node Generator
# https://github.com/vernette/warpscout

$ErrorActionPreference = "Stop"

$Repo = "vernette/warpscout"
$WorkDir = Split-Path -Parent $PSScriptRoot
$ToolDir = Join-Path $WorkDir "tools"
$WarpDir = Join-Path $ToolDir "warpscout"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "       WARP MASQUE-H2 Multi-Node" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# 1. Prepare directories
# ------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null
New-Item -ItemType Directory -Force -Path $WarpDir | Out-Null

$WarpExe = Join-Path $WarpDir "warpscout.exe"

# ------------------------------------------------------------
# 2. Download latest warpscout
# ------------------------------------------------------------

if (-not (Test-Path $WarpExe)) {

    Write-Host "[1/4] Downloading latest warpscout..." -ForegroundColor Yellow

    $ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"

    $Release = Invoke-RestMethod `
        -Uri $ApiUrl `
        -Headers @{
            "User-Agent" = "WARP-MultiNode"
        }

    $Asset = $Release.assets |
        Where-Object { $_.name -match "windows_amd64\.zip$" } |
        Select-Object -First 1

    if (-not $Asset) {
        throw "Cannot find Windows AMD64 warpscout release."
    }

    $ZipFile = Join-Path $ToolDir "warpscout.zip"

    Write-Host "Version: $($Release.tag_name)" -ForegroundColor Green
    Write-Host "Downloading: $($Asset.name)"

    Invoke-WebRequest `
        -Uri $Asset.browser_download_url `
        -OutFile $ZipFile

    Expand-Archive `
        -Path $ZipFile `
        -DestinationPath $WarpDir `
        -Force

    Remove-Item $ZipFile -Force

    # Handle possible nested directory
    $FoundExe = Get-ChildItem `
        -Path $WarpDir `
        -Filter "warpscout.exe" `
        -Recurse |
        Select-Object -First 1

    if (-not $FoundExe) {
        throw "warpscout.exe was not found after extraction."
    }

    if ($FoundExe.FullName -ne $WarpExe) {
        Copy-Item `
            $FoundExe.FullName `
            $WarpExe `
            -Force
    }

    Write-Host "warpscout installed successfully." -ForegroundColor Green

} else {

    Write-Host "[1/4] warpscout already exists." -ForegroundColor Green
}

# ------------------------------------------------------------
# 3. Register WARP account if needed
# ------------------------------------------------------------

Set-Location $WarpDir

$AccountFile = Join-Path $WarpDir "warpscout-account.json"

if (-not (Test-Path $AccountFile)) {

    Write-Host ""
    Write-Host "[2/4] Registering WARP account..." -ForegroundColor Yellow

    & $WarpExe register

    if ($LASTEXITCODE -ne 0) {
        throw "WARP account registration failed."
    }

} else {

    Write-Host ""
    Write-Host "[2/4] Existing WARP account detected." -ForegroundColor Green
}

# ------------------------------------------------------------
# 4. Scan MASQUE-H2
# ------------------------------------------------------------

Write-Host ""
Write-Host "[3/4] Scanning MASQUE-H2 endpoints..." -ForegroundColor Yellow
Write-Host "This may take around one minute."
Write-Host ""

& $WarpExe scan `
    -p masque-h2 `
    -n 280 `
    -conf best.yaml `
    -conf-type mihomo

if ($LASTEXITCODE -ne 0) {
    throw "warpscout scan failed."
}

# ------------------------------------------------------------
# 5. Find latest report
# ------------------------------------------------------------

$Report = Get-ChildItem `
    -Path $WarpDir `
    -Filter "warpscout-report-*.txt" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Report) {
    throw "warpscout report not found."
}

# ------------------------------------------------------------
# 6. Read best configuration
# ------------------------------------------------------------

$BestConfig = Get-Content `
    -Path (Join-Path $WarpDir "best.yaml") `
    -Raw

$PrivateKey = [regex]::Match(
    $BestConfig,
    '(?m)^\s*private-key:\s*(\S+)'
).Groups[1].Value

$PublicKey = [regex]::Match(
    $BestConfig,
    '(?m)^\s*public-key:\s*(\S+)'
).Groups[1].Value

$IP = [regex]::Match(
    $BestConfig,
    '(?m)^\s*ip:\s*(\S+)'
).Groups[1].Value

$SNI = [regex]::Match(
    $BestConfig,
    '(?m)^\s*sni:\s*(\S+)'
).Groups[1].Value

if (-not $PrivateKey -or -not $PublicKey -or -not $IP) {
    throw "Failed to extract WARP credentials."
}

# ------------------------------------------------------------
# 7. Extract all working endpoints
# ------------------------------------------------------------

$Endpoints = Get-Content $Report.FullName |
    ForEach-Object {

        if ($_ -match '^\s*(\d{1,3}(?:\.\d{1,3}){3}):(\d+)\s+(\d+(?:\.\d+)?)ms') {

            [PSCustomObject]@{
                IP   = $Matches[1]
                Port = $Matches[2]
                Ping = $Matches[3]
            }
        }
    }

if (-not $Endpoints -or $Endpoints.Count -eq 0) {
    throw "No working MASQUE-H2 endpoints found."
}

# Remove duplicates while keeping order
$Endpoints = $Endpoints |
    Sort-Object IP, Port -Unique

Write-Host ""
Write-Host "Working endpoints: $($Endpoints.Count)" -ForegroundColor Green

# ------------------------------------------------------------
# 8. Generate multi-node Mihomo configuration
# ------------------------------------------------------------

$OutputFile = Join-Path $WorkDir "warp-multi.yaml"

$Yaml = New-Object System.Collections.Generic.List[string]

$Yaml.Add("mixed-port: 7890")
$Yaml.Add("allow-lan: false")
$Yaml.Add("mode: rule")
$Yaml.Add("")
$Yaml.Add("proxies:")

$Index = 1

foreach ($Endpoint in $Endpoints) {

    $Name = "WARP-H2-{0:D2}" -f $Index

    $Yaml.Add("  - name: `"$Name | $($Endpoint.Ping)ms`"")
    $Yaml.Add("    type: masque")
    $Yaml.Add("    server: $($Endpoint.IP)")
    $Yaml.Add("    port: $($Endpoint.Port)")
    $Yaml.Add("    network: h2")
    $Yaml.Add("    sni: $SNI")
    $Yaml.Add("    private-key: $PrivateKey")
    $Yaml.Add("    public-key: $PublicKey")
    $Yaml.Add("    ip: $IP")
    $Yaml.Add("    udp: true")
    $Yaml.Add("    remote-dns-resolve: true")
    $Yaml.Add("    dns: ['1.1.1.1', '1.0.0.1']")
    $Yaml.Add("")

    $Index++
}

$Yaml.Add("proxy-groups:")
$Yaml.Add("  - name: WARP")
$Yaml.Add("    type: url-test")
$Yaml.Add("    proxies:")

for ($i = 1; $i -lt $Index; $i++) {

    $Name = "WARP-H2-{0:D2}" -f $i

    $Yaml.Add("      - `"$Name`"")
}

$Yaml.Add("    url: https://www.cloudflare.com/cdn-cgi/trace")
$Yaml.Add("    interval: 300")
$Yaml.Add("")
$Yaml.Add("rules:")
$Yaml.Add("  - MATCH,WARP")

$Yaml |
    Set-Content `
        -Path $OutputFile `
        -Encoding UTF8

# ------------------------------------------------------------
# 9. Finish
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "              COMPLETED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Working endpoints : $($Endpoints.Count)"
Write-Host "Output file        : $OutputFile"
Write-Host ""
Write-Host "Import warp-multi.yaml into your Mihomo/Clash client."
Write-Host ""
