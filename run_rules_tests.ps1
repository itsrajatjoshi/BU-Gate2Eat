# YummBU / BU Gate2Eat — Firestore Security Rules Automated Runner
$ErrorActionPreference = "Stop"

$jarPath = "$env:USERPROFILE\.cache\firebase\emulators\cloud-firestore-emulator-v1.22.0.jar"
$javaPath = "C:\Program Files\Java\latest\jdk-25\bin\java.exe"
$rulesPath = "firestore.rules"
$logPath = "$env:TEMP\firestore-emulator-out.log"
$errPath = "$env:TEMP\firestore-emulator-err.log"

Write-Host "Starting Cloud Firestore Emulator on 127.0.0.1:8080..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $javaPath -ArgumentList @('-jar', $jarPath, '--host', '127.0.0.1', '--port', '8080', '--rules', $rulesPath) -RedirectStandardError $errPath -RedirectStandardOutput $logPath -PassThru -WindowStyle Hidden

# Wait for emulator to become ready
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $res = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/' -TimeoutSec 1 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($res.StatusCode -eq 200) {
            $ready = $true
            break
        }
    } catch {}
}

if (-not $ready) {
    Write-Host "Failed to start Firestore Emulator within timeout!" -ForegroundColor Red
    if (Test-Path $logPath) {
        Write-Host "Emulator Log:" -ForegroundColor Yellow
        Get-Content $logPath
    }
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Firestore Emulator is ready! Running Rules Unit Tests..." -ForegroundColor Green

$exitCode = 0
try {
    & node functions/test_firestore_rules.js
    $exitCode = $LASTEXITCODE
} finally {
    Write-Host "Stopping Firestore Emulator..." -ForegroundColor Cyan
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}

exit $exitCode
