@echo off
setlocal EnableExtensions DisableDelayedExpansion

title WARP MASQUE-H2 Node Generator

cd /d "%~dp0"

echo.
echo ==========================================
echo   Cloudflare WARP MASQUE-H2 Generator
echo ==========================================
echo.

REM ============================================================
REM Basic environment check
REM ============================================================

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Windows PowerShell was not found.
    echo.
    pause
    exit /b 1
)

echo [1/6] Checking Windows environment...

powershell.exe -NoProfile -Command "$v=$PSVersionTable.PSVersion; Write-Host ('Windows PowerShell ' + $v.Major + '.' + $v.Minor)"

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to start Windows PowerShell.
    echo.
    pause
    exit /b 1
)

REM ============================================================
REM Directory setup
REM ============================================================

set "WORK_DIR=%~dp0"
set "TOOLS_DIR=%WORK_DIR%tools"
set "WARP_DIR=%TOOLS_DIR%\warpscout"
set "WARP_EXE=%WARP_DIR%\warpscout.exe"
set "ZIP_FILE=%TOOLS_DIR%\warpscout.zip"
set "ACCOUNT_FILE=%WARP_DIR%\warpscout-account.json"
set "REPORT_FILE=%WARP_DIR%\scan-report.txt"
set "BEST_FILE=%WARP_DIR%\best.yaml"
set "OUTPUT_FILE=%WORK_DIR%warp-multi.yaml"

if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
if not exist "%WARP_DIR%" mkdir "%WARP_DIR%"

REM ============================================================
REM Download latest warpscout
REM ============================================================

echo.
echo [2/6] Checking warpscout...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $api='https://api.github.com/repos/vernette/warpscout/releases/latest'; $r=Invoke-RestMethod -Uri $api -UseBasicParsing; $a=$r.assets | Where-Object { $_.name -eq 'windows_amd64.zip' } | Select-Object -First 1; if (-not $a) { throw 'windows_amd64.zip was not found in the latest release.' }; Write-Host ('Latest version: ' + $r.tag_name); Write-Host ('Download: ' + $a.name); if (Test-Path '%WARP_EXE%') { $old=(Get-Item '%WARP_EXE%').Length; Write-Host ('Existing warpscout.exe found (' + $old + ' bytes).'); } else { Invoke-WebRequest -Uri $a.browser_download_url -OutFile '%ZIP_FILE%' -UseBasicParsing; Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%WARP_DIR%' -Force; Remove-Item '%ZIP_FILE%' -Force; }; if (-not (Test-Path '%WARP_EXE%')) { throw 'warpscout.exe was not found after extraction.' }"

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to download or prepare warpscout.
    echo.
    pause
    exit /b 1
)

REM ============================================================
REM Register WARP account
REM ============================================================

echo.
echo [3/6] Checking WARP account...

if exist "%ACCOUNT_FILE%" (
    echo Existing WARP account found.
) else (
    echo No WARP account found.
    echo Registering a new WARP account...
    echo.

    pushd "%WARP_DIR%"

    "%WARP_EXE%" register

    if errorlevel 1 (
        popd
        echo.
        echo [ERROR] WARP account registration failed.
        echo.
        pause
        exit /b 1
    )

    popd

    echo.
    echo WARP account registration completed.
)

REM ============================================================
REM Scan MASQUE-H2 endpoints
REM ============================================================

echo.
echo [4/6] Scanning MASQUE-H2 endpoints...
echo.
echo This may take a while.
echo Please do not close this window.
echo.

if exist "%REPORT_FILE%" del /f /q "%REPORT_FILE%" >nul 2>&1
if exist "%BEST_FILE%" del /f /q "%BEST_FILE%" >nul 2>&1

pushd "%WARP_DIR%"

"%WARP_EXE%" scan -p masque-h2 -n 280 -o "%REPORT_FILE%" -conf "%BEST_FILE%" -conf-type mihomo

set "SCAN_RESULT=%ERRORLEVEL%"

popd

if not "%SCAN_RESULT%"=="0" (
    echo.
    echo [ERROR] MASQUE-H2 scan failed.
    echo.
    echo Possible reasons:
    echo   - Network connection problem
    echo   - GitHub or Cloudflare temporarily unavailable
    echo   - WARP registration failed
    echo.
    pause
    exit /b 1
)

if not exist "%REPORT_FILE%" (
    echo.
    echo [ERROR] Scan report was not generated.
    echo.
    pause
    exit /b 1
)

if not exist "%BEST_FILE%" (
    echo.
    echo [ERROR] Best endpoint configuration was not generated.
    echo.
    pause
    exit /b 1
)

REM ============================================================
REM Generate multi-node Mihomo configuration
REM ============================================================

echo.
echo [5/6] Generating multi-node Mihomo configuration...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $report=Get-Content '%REPORT_FILE%' -Raw; $best=Get-Content '%BEST_FILE%' -Raw; $pk=[regex]::Match($best,'(?m)^\s*private-key:\s*(\S+)').Groups[1].Value; $pub=[regex]::Match($best,'(?m)^\s*public-key:\s*(\S+)').Groups[1].Value; $ip=[regex]::Match($best,'(?m)^\s*ip:\s*(\S+)').Groups[1].Value; $ipv6=[regex]::Match($best,'(?m)^\s*ipv6:\s*(\S+)').Groups[1].Value; $sni=[regex]::Match($best,'(?m)^\s*sni:\s*(\S+)').Groups[1].Value; if ([string]::IsNullOrWhiteSpace($pk)) { throw 'private-key was not found in best.yaml.' }; if ([string]::IsNullOrWhiteSpace($pub)) { throw 'public-key was not found in best.yaml.' }; if ([string]::IsNullOrWhiteSpace($ip)) { throw 'WARP IPv4 address was not found in best.yaml.' }; if ([string]::IsNullOrWhiteSpace($sni)) { $sni='consumer-masque.cloudflareclient.com' }; $matches=[regex]::Matches($report,'(?m)^\s*(\d{1,3}(?:\.\d{1,3}){3}):(\d+)\s+'); $seen=@{}; $nodes=New-Object System.Collections.Generic.List[object]; foreach($m in $matches){ $host=$m.Groups[1].Value; $port=$m.Groups[2].Value; $key=$host+':'+$port; if(-not $seen.ContainsKey($key)){ $seen[$key]=$true; $nodes.Add([PSCustomObject]@{Host=$host;Port=$port}) } }; if($nodes.Count -eq 0){ throw 'No working MASQUE-H2 endpoints were found.' }; $lines=New-Object System.Collections.Generic.List[string]; $lines.Add('proxies:'); $i=1; foreach($n in $nodes){ $lines.Add(('  - name: ''WARP-H2-{0:D2}''' -f $i)); $lines.Add('    type: masque'); $lines.Add(('    server: {0}' -f $n.Host)); $lines.Add(('    port: {0}' -f $n.Port)); $lines.Add('    network: h2'); $lines.Add(('    sni: {0}' -f $sni)); $lines.Add(('    private-key: {0}' -f $pk)); $lines.Add(('    public-key: {0}' -f $pub)); $lines.Add(('    ip: {0}' -f $ip)); if(-not [string]::IsNullOrWhiteSpace($ipv6)){ $lines.Add(('    ipv6: {0}' -f $ipv6)) }; $lines.Add('    udp: true'); $lines.Add('    remote-dns-resolve: true'); $lines.Add('    dns: [''1.1.1.1'', ''1.0.0.1'']'); $lines.Add(''); $i++ }; $lines.Add('proxy-groups:'); $lines.Add('  - name: WARP-AUTO'); $lines.Add('    type: url-test'); $lines.Add('    proxies:'); for($j=1;$j -le $nodes.Count;$j++){ $lines.Add(('      - WARP-H2-{0:D2}' -f $j)) }; $lines.Add('    url: https://www.cloudflare.com/cdn-cgi/trace'); $lines.Add('    interval: 300'); $lines.Add('    tolerance: 50'); $lines.Add(''); $lines.Add('rules:'); $lines.Add('  - MATCH,WARP-AUTO'); [IO.File]::WriteAllLines('%OUTPUT_FILE%',$lines,(New-Object Text.UTF8Encoding($false))); Write-Host ('Working endpoints: ' + $nodes.Count); Write-Host ('Configuration: %OUTPUT_FILE%')"

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to generate warp-multi.yaml.
    echo.
    pause
    exit /b 1
)

if not exist "%OUTPUT_FILE%" (
    echo.
    echo [ERROR] warp-multi.yaml was not created.
    echo.
    pause
    exit /b 1
)

REM ============================================================
REM Finish
REM ============================================================

echo.
echo [6/6] Completed.
echo.
echo ==========================================
echo   WARP MASQUE-H2 configuration generated
echo ==========================================
echo.
echo Output:
echo %OUTPUT_FILE%
echo.
echo You can now import warp-multi.yaml into a Mihomo/Clash client.
echo.
echo The generated WARP-AUTO group will automatically test
echo the available MASQUE-H2 endpoints.
echo.
pause

endlocal
exit /b 0
