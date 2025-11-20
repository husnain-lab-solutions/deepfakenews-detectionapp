param(
    [string]$JobName = "TrainText",
    [string]$OutputDir = "models\\text-fakenews",
    [int]$Port = 8000,
    [string]$BindHost = "127.0.0.1"
)

$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
try {
    function Has-ModelFiles($dir) {
        $cfg = Test-Path (Join-Path $dir 'config.json')
        $tok = Test-Path (Join-Path $dir 'tokenizer.json')
        $bin = Test-Path (Join-Path $dir 'pytorch_model.bin')
        $sft = Test-Path (Join-Path $dir 'model.safetensors')
        return ($cfg -and $tok -and ($bin -or $sft))
    }

    $outPath = Join-Path $PSScriptRoot $OutputDir
    if (-not (Test-Path $outPath)) { New-Item -ItemType Directory -Path $outPath | Out-Null }

    $job = Get-Job -Name $JobName -ErrorAction SilentlyContinue
    if ($null -eq $job) {
        Write-Host "No job named '$JobName' found. Waiting for model files to appear at $outPath ..." -ForegroundColor Yellow
        while (-not (Has-ModelFiles $outPath)) { Start-Sleep -Seconds 10 }
    }
    else {
        Write-Host "Waiting for training job '$JobName' to finish..." -ForegroundColor Cyan
        Wait-Job -Name $JobName | Out-Null
        Write-Host "Training job completed. Collecting logs..." -ForegroundColor Cyan
        try { Receive-Job -Name $JobName -Keep | Write-Host } catch {}
        $state = (Get-Job -Name $JobName).State
        if ($state -ne 'Completed') {
            Write-Host "Job state: $state. If 'Failed', check the logs above." -ForegroundColor Yellow
        }
    }

    if (-not (Has-ModelFiles $outPath)) {
        Write-Host "Trained model artifacts not found in $outPath. Aborting switch." -ForegroundColor Red
        exit 1
    }

    Write-Host "Switching ML service to trained model at $outPath ..." -ForegroundColor Green
    # Stop existing detached server if any
    .\run_ml.ps1 -Stop | Out-Null
    # Start with trained model in classifier mode
    .\run_ml.ps1 -UseHF -Model $outPath -TextMode classifier -Port $Port -Detached | Out-Null
    Write-Host ("ML service restarted on http://{0}:{1} using trained model." -f $BindHost, $Port) -ForegroundColor Green
}
finally {
    Pop-Location
}