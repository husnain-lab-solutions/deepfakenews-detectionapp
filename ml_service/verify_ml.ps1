param(
    [string]$BindHost = "127.0.0.1",
    [int]$Port = 8000,
    [int]$WaitSeconds = 120
)

$ErrorActionPreference = 'Stop'

$base = ("http://{0}:{1}" -f $BindHost, $Port)
Write-Host "Verifying ML service at $base ..." -ForegroundColor Cyan

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$healthy = $false
while ((Get-Date) -lt $deadline) {
    try {
        $resp = Invoke-RestMethod -Uri ("{0}/health" -f $base) -TimeoutSec 3 -ErrorAction Stop
        if ($resp.status -eq 'OK') { $healthy = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
}

if (-not $healthy) {
    Write-Host "Service did not become healthy within $WaitSeconds seconds." -ForegroundColor Red
    exit 1
}

Write-Host "Health OK. Running sample predictions..." -ForegroundColor Green

function Invoke-PredictText([string]$text) {
    $body = @{ text = $text } | ConvertTo-Json -Depth 3
    return Invoke-RestMethod -Uri ("{0}/predict-text" -f $base) -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 10
}

$sample1 = "The government approved a new education budget."
$sample2 = "The vaccine contains microchips to track people."

try {
    $r1 = Invoke-PredictText $sample1
    $r2 = Invoke-PredictText $sample2
    Write-Host "Sample 1: '$sample1' -> Label=$($r1.label) Confidence=$([math]::Round([double]$r1.confidence,3))" -ForegroundColor Yellow
    Write-Host "Sample 2: '$sample2' -> Label=$($r2.label) Confidence=$([math]::Round([double]$r2.confidence,3))" -ForegroundColor Yellow
    Write-Host "Verification complete." -ForegroundColor Green
} catch {
    Write-Host "Prediction calls failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}