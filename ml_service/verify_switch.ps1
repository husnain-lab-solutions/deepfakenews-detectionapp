param(
    [string]$Host = "127.0.0.1",
    [int]$Port = 8000,
    [string]$ExpectModelContains = "models\\text-fakenews",
    [int]$TimeoutSec = 600
)

$ErrorActionPreference = 'Stop'

function Wait-Until($ScriptBlock, [int]$Timeout) {
    $deadline = (Get-Date).AddSeconds($Timeout)
    while((Get-Date) -lt $deadline) {
        if (& $ScriptBlock) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

Push-Location $PSScriptRoot
try {
    Write-Host "Waiting for watcher to complete or service to report healthy..." -ForegroundColor Cyan

    $ok = Wait-Until -Timeout $TimeoutSec -ScriptBlock {
        try {
            $h = Invoke-RestMethod -Uri "http://$Host:$Port/health" -TimeoutSec 3 -ErrorAction Stop
            return $h.status -eq 'OK'
        } catch { return $false }
    }
    if (-not $ok) { Write-Host "Service did not become healthy in time." -ForegroundColor Red; exit 1 }

    $info = $null
    try { $info = Invoke-RestMethod -Uri "http://$Host:$Port/info" -TimeoutSec 5 -ErrorAction Stop } catch { }
    if ($info) {
        Write-Host "Service Info: use_hf=$($info.use_hf) mode=$($info.text_mode) model=$($info.text_classifier_model)" -ForegroundColor DarkGray
        if ($ExpectModelContains -and ($info.text_classifier_model -notmatch [regex]::Escape($ExpectModelContains))) {
            Write-Host "Warning: model path does not contain expected segment '$ExpectModelContains'" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Info endpoint unavailable; continuing with health-only verification." -ForegroundColor Yellow
    }

    $sample = @{ text = "The government announced a new education policy today." } | ConvertTo-Json -Compress
    $pred = Invoke-RestMethod -Method Post -Uri "http://$Host:$Port/predict-text" -ContentType 'application/json' -Body $sample -TimeoutSec 10
    Write-Host "Sample prediction: label=$($pred.label) confidence=$([math]::Round([double]$pred.confidence,3))" -ForegroundColor Green
    exit 0
}
finally {
    Pop-Location
}