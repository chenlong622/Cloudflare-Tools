# WARP - Cloudflare WARP MASQUE-H2 多节点生成工具
# 上游项目：https://github.com/vernette/warpscout

$ErrorActionPreference = "Stop"

$Repo = "vernette/warpscout"
$WorkDir = $PSScriptRoot
$ToolDir = Join-Path $WorkDir "tools"
$WarpDir = Join-Path $ToolDir "warpscout"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "     WARP MASQUE-H2 多节点生成工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# 1. 准备目录
# ------------------------------------------------------------

Write-Host "[1/4] 正在检查 WARP 扫描工具..." -ForegroundColor Yellow

New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null
New-Item -ItemType Directory -Force -Path $WarpDir | Out-Null

$WarpExe = Join-Path $WarpDir "warpscout.exe"

# ------------------------------------------------------------
# 2. 自动下载最新版 warpscout
# ------------------------------------------------------------

if (-not (Test-Path $WarpExe)) {

    Write-Host "未发现 warpscout，正在下载最新版..." -ForegroundColor Yellow

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
        throw "无法找到 Windows AMD64 版本的 warpscout。"
    }

    $ZipFile = Join-Path $ToolDir "warpscout.zip"

    Write-Host "检测到最新版：$($Release.tag_name)" -ForegroundColor Green
    Write-Host "正在下载：$($Asset.name)"

    Invoke-WebRequest `
        -Uri $Asset.browser_download_url `
        -OutFile $ZipFile

    Expand-Archive `
        -Path $ZipFile `
        -DestinationPath $WarpDir `
        -Force

    Remove-Item $ZipFile -Force

    $FoundExe = Get-ChildItem `
        -Path $WarpDir `
        -Filter "warpscout.exe" `
        -Recurse |
        Select-Object -First 1

    if (-not $FoundExe) {
        throw "warpscout 下载完成，但没有找到 warpscout.exe。"
    }

    if ($FoundExe.FullName -ne $WarpExe) {
        Copy-Item `
            $FoundExe.FullName `
            $WarpExe `
            -Force
    }

    Write-Host "warpscout 安装完成。" -ForegroundColor Green

} else {

    Write-Host "已检测到 warpscout，无需重复下载。" -ForegroundColor Green
}

# ------------------------------------------------------------
# 3. 检查 / 注册 WARP 账户
# ------------------------------------------------------------

Set-Location $WarpDir

$AccountFile = Join-Path $WarpDir "warpscout-account.json"

Write-Host ""
Write-Host "[2/4] 正在检查 WARP 账户..." -ForegroundColor Yellow

if (-not (Test-Path $AccountFile)) {

    Write-Host "未发现 WARP 账户，正在注册新账户..." -ForegroundColor Yellow

    $RegisterOutput = & $WarpExe register 2>&1

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "WARP 账户注册失败。" -ForegroundColor Red
        Write-Host ""
        Write-Host $RegisterOutput
        exit 1
    }

    Write-Host "WARP 账户注册成功。" -ForegroundColor Green

} else {

    Write-Host "已发现本地 WARP 账户，将继续使用。" -ForegroundColor Green
}

# ------------------------------------------------------------
# 4. 扫描 MASQUE-H2 Endpoint
# ------------------------------------------------------------

Write-Host ""
Write-Host "[3/4] 正在扫描 MASQUE-H2 Endpoint..." -ForegroundColor Yellow
Write-Host ""
Write-Host "扫描范围：280 个 Endpoint"
Write-Host "这个过程可能需要几十秒，请耐心等待..."
Write-Host ""

$ScanOutput = & $WarpExe scan `
    -p masque-h2 `
    -n 280 `
    -conf best.yaml `
    -conf-type mihomo 2>&1

if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "MASQUE-H2 扫描失败。" -ForegroundColor Red
    Write-Host ""
    Write-Host "错误信息："
    Write-Host $ScanOutput
    exit 1
}

Write-Host "Endpoint 扫描完成。" -ForegroundColor Green

# ------------------------------------------------------------
# 5. 查找最新扫描报告
# ------------------------------------------------------------

$Report = Get-ChildItem `
    -Path $WarpDir `
    -Filter "warpscout-report-*.txt" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $Report) {
    throw "没有找到 warpscout 扫描报告。"
}

# ------------------------------------------------------------
# 6. 读取最佳节点配置
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
    throw "无法从 warpscout 配置中读取 WARP 密钥信息。"
}

# ------------------------------------------------------------
# 7. 提取所有可用 Endpoint
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

    Write-Host ""
    Write-Host "没有发现可用的 MASQUE-H2 Endpoint。" -ForegroundColor Red
    exit 1
}

# 删除重复 Endpoint
$Endpoints = $Endpoints |
    Sort-Object IP, Port -Unique

# ------------------------------------------------------------
# 8. 显示扫描结果
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "             扫描结果" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "发现可用 Endpoint：$($Endpoints.Count) 个" -ForegroundColor Green
Write-Host ""

$BestEndpoint = $Endpoints | Select-Object -First 1

Write-Host "最快 Endpoint：" -ForegroundColor Cyan
Write-Host "$($BestEndpoint.IP):$($BestEndpoint.Port)"
Write-Host "延迟：$($BestEndpoint.Ping)ms"
Write-Host ""

# ------------------------------------------------------------
# 9. 生成多节点 Mihomo 配置
# ------------------------------------------------------------

Write-Host "[4/4] 正在生成 Mihomo 多节点配置..." -ForegroundColor Yellow

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
# 10. 完成
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "              生成完成" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "可用节点：$($Endpoints.Count) 个" -ForegroundColor Green
Write-Host "配置文件：$OutputFile"
Write-Host ""

Write-Host "请将 warp-multi.yaml 导入 Mihomo / Clash 系客户端。" -ForegroundColor Cyan
Write-Host ""
