param(
    [string]$JobName = "TrainText",
    [string]$Dataset = "liar",
    [int]$Epochs = 3,
    [int]$BatchSize = 16,
    [string]$OutputDir = "models\\text-fakenews",
    [int]$Port = 8000
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    if (-not (Test-Path .\.venv\Scripts\python.exe)) {
        Write-Host "Python venv not found. Please run run_ml.ps1 once to set it up." -ForegroundColor Red
        exit 1
    }

    $py = ".\.venv\Scripts\python.exe"
    Write-Host "Starting training job '$JobName' (dataset=$Dataset, epochs=$Epochs, batch-size=$BatchSize) ..." -ForegroundColor Cyan
    $args = @('train_text_classifier.py', '--dataset', $Dataset, '--epochs', $Epochs, '--batch-size', $BatchSize, '--output-dir', $OutputDir)
    Start-Job -Name $JobName -ScriptBlock { param($p,$a) Set-Location $p; & .\.venv\Scripts\python.exe @a } -ArgumentList (Get-Location).Path, $args | Out-Null

    Write-Host "Watcher armed. Will switch to trained model when finished." -ForegroundColor Green
    .\watch_train_and_switch.ps1 -JobName $JobName -OutputDir $OutputDir -Port $Port
}
finally {
    Pop-Location
}