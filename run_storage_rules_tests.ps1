# YummBU / BU Gate2Eat — Firebase Storage Security Rules Automated Runner
$ErrorActionPreference = "Stop"

# Clear port 9199 if lingering from a previous run
try {
    $existing = Get-NetTCPConnection -LocalPort 9199 -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Clearing existing process on port 9199..." -ForegroundColor Yellow
        foreach ($conn in $existing) {
            cmd /c "taskkill /PID $($conn.OwningProcess) /T /F" 2>$null
        }
        Start-Sleep -Seconds 1
    }
} catch {}

$logFile = "$env:TEMP\storage-out.log"
$errFile = "$env:TEMP\storage-err.log"
if (Test-Path $logFile) { Remove-Item $logFile -Force }
if (Test-Path $errFile) { Remove-Item $errFile -Force }

Write-Host "Starting Firebase Storage Emulator on 127.0.0.1:9199..." -ForegroundColor Cyan

$batPath = Join-Path $PSScriptRoot "start_emulator.bat"
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList @('/c', 'start_emulator.bat') -WorkingDirectory $PSScriptRoot -PassThru -WindowStyle Hidden

# Wait for emulator to become ready
$ready = $false
for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $res = Invoke-WebRequest -Uri 'http://127.0.0.1:9199/' -TimeoutSec 1 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($res.StatusCode -eq 200) {
            $ready = $true
            break
        }
    } catch {}
    
    $listening = Get-NetTCPConnection -LocalPort 9199 -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        $ready = $true
        break
    }
}

if (-not $ready) {
    Write-Host "Failed to start Storage Emulator within timeout!" -ForegroundColor Red
    if (Test-Path $logFile) { Write-Host "--- STDOUT ---"; Get-Content $logFile }
    if (Test-Path $errFile) { Write-Host "--- STDERR ---"; Get-Content $errFile }
    try { cmd /c "taskkill /PID $($proc.Id) /T /F" 2>$null } catch {}
    exit 1
}

Write-Host "Storage Emulator is ready! Running Storage Rules Unit Tests..." -ForegroundColor Green

$exitCode = 0
try {
    & node functions/test_storage_rules.js
    $exitCode = $LASTEXITCODE
} finally {
    Write-Host "Stopping Storage Emulator..." -ForegroundColor Cyan
    try {
        cmd /c "taskkill /PID $($proc.Id) /T /F" 2>$null
    } catch {}
    
    # Ensure port 9199 is clean
    Start-Sleep -Milliseconds 500
    try {
        $lingering = Get-NetTCPConnection -LocalPort 9199 -ErrorAction SilentlyContinue
        if ($lingering) {
            foreach ($conn in $lingering) {
                cmd /c "taskkill /PID $($conn.OwningProcess) /T /F" 2>$null
            }
        }
    } catch {}
}

exit $exitCode
