param(
    [int]$Port = 8000,
    [string]$BindHost = "127.0.0.1",
    [switch]$UseHF,
    [switch]$NewWindow,
    [switch]$Detached,             # Run uvicorn as a detached background process (logs to files)
    [switch]$Stop,                 # Stop the detached uvicorn process if running
    [string]$Model = "",           # Hugging Face model id for a fake-news text classifier
    [ValidateSet("auto", "classifier", "heuristic")]
    [string]$TextMode = "auto",    # How to choose text pipeline
    [switch]$AllowDownloads,         # Allow model downloads (set HF_ALLOW_DOWNLOADS=1)
    [string]$ZeroShotTemplate = "", # Optional override for zero-shot hypothesis template
    [string]$ZeroShotLabels = "",   # Optional comma-separated labels for zero-shot (e.g., "fake,real")
    [int]$WaitHealthSeconds = 90     # When -NewWindow, wait up to N seconds for /health
)

$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
try {
    # Stop request to terminate detached uvicorn
    if ($Stop) {
        $pidFile = Join-Path $PSScriptRoot 'uvicorn.pid'
        if (Test-Path $pidFile) {
            $uvPid = Get-Content $pidFile | Select-Object -First 1
            if ($uvPid) {
                Write-Host "Stopping uvicorn PID $uvPid ..." -ForegroundColor Yellow
                try { Stop-Process -Id [int]$uvPid -Force } catch { }
                Remove-Item $pidFile -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Host "No uvicorn.pid file found. Nothing to stop." -ForegroundColor Yellow
        }
        return
    }
    if (-not (Test-Path .\.venv\Scripts\Activate.ps1)) {
        Write-Host "Virtual environment not found (.venv). Creating one..." -ForegroundColor Yellow
        python -m venv .venv
    }
    . .\.venv\Scripts\Activate.ps1

    Write-Host "Ensuring required packages from requirements.txt ..." -ForegroundColor Cyan
    python -m pip install --upgrade pip | Out-Null
    if (Test-Path .\requirements.txt) {
        python -m pip install -r requirements.txt | Out-Null
    }
    else {
        python -m pip install uvicorn fastapi pillow transformers | Out-Null
    }

    if ($UseHF) {
        Write-Host "Enabling HuggingFace models (USE_HF=1). Ensure internet access and cached models." -ForegroundColor Yellow
        $env:USE_HF = '1'
    }
    else {
        Write-Host "Running in fast/offline mode (USE_HF=0) - heuristic predictions, no downloads." -ForegroundColor Yellow
        $env:USE_HF = '0'
    }

    # Optional text classifier model and mode
    if ($Model -ne "") {
        Write-Host "Using text classifier model: $Model" -ForegroundColor Yellow
        $env:TEXT_CLASSIFIER_MODEL = $Model
    }
    if ($TextMode) {
        $env:TEXT_MODE = $TextMode
    }
    if ($AllowDownloads) {
        Write-Host "Allowing model downloads (HF_ALLOW_DOWNLOADS=1)" -ForegroundColor Yellow
        $env:HF_ALLOW_DOWNLOADS = '1'
    }
    else {
        $env:HF_ALLOW_DOWNLOADS = '0'
    }

    # Optional zero-shot tuning
    if ($ZeroShotTemplate -ne "") {
        Write-Host "Using ZERO_SHOT_TEMPLATE: $ZeroShotTemplate" -ForegroundColor Yellow
        $env:ZERO_SHOT_TEMPLATE = $ZeroShotTemplate
    }
    if ($ZeroShotLabels -ne "") {
        Write-Host "Using ZERO_SHOT_CANDIDATES: $ZeroShotLabels" -ForegroundColor Yellow
        $env:ZERO_SHOT_CANDIDATES = $ZeroShotLabels
    }

    if ($Detached) {
        # Launch uvicorn as detached background process, logging to files
        $pythonwPath = Join-Path $PSScriptRoot '.venv\Scripts\pythonw.exe'
        $pythonPath = if (Test-Path $pythonwPath) { $pythonwPath } else { (Join-Path $PSScriptRoot '.venv\Scripts\python.exe') }
        if (-not (Test-Path $pythonPath)) { $pythonPath = 'pythonw' }
        $outLog = Join-Path $PSScriptRoot 'uvicorn.out.log'
        $errLog = Join-Path $PSScriptRoot 'uvicorn.err.log'
        $pidFile = Join-Path $PSScriptRoot 'uvicorn.pid'
        Write-Host "Starting uvicorn detached on ${BindHost}:$Port ..." -ForegroundColor Green
        $args = @('-m', 'uvicorn', 'app:app', '--host', $BindHost, '--port', "$Port", '--log-level', 'info')
        $proc = Start-Process -FilePath $pythonPath -ArgumentList $args -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
        Set-Content -Path $pidFile -Value $proc.Id
        # Poll health
        $deadline = (Get-Date).AddSeconds($WaitHealthSeconds)
        $healthy = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            try {
                $r = Invoke-RestMethod -Uri "http://${BindHost}:$Port/health" -TimeoutSec 3 -ErrorAction Stop
                if ($r.status -eq 'OK') { $healthy = $true; break }
            }
            catch { }
        }
        if ($healthy) {
            Write-Host "ML service is up at http://${BindHost}:$Port (PID $($proc.Id)). Logs: $outLog, $errLog" -ForegroundColor Green
        }
        else {
            Write-Host "ML service did not respond to /health within $WaitHealthSeconds seconds." -ForegroundColor Yellow
            Write-Host "Check logs: $outLog and $errLog" -ForegroundColor Yellow
        }
    }
    elseif ($NewWindow) {
        Write-Host "Launching new PowerShell window to keep the server running..." -ForegroundColor Green
        # Escape $ so that the child window sets $env:USE_HF instead of expanding it here
        $hf = $env:USE_HF
        $model = $env:TEXT_CLASSIFIER_MODEL
        $textMode = $env:TEXT_MODE
        $allow = $env:HF_ALLOW_DOWNLOADS
        $zsTemplate = $env:ZERO_SHOT_TEMPLATE
        $zsLabels = $env:ZERO_SHOT_CANDIDATES
        $cmd = "cd `"$PSScriptRoot`"; . .\.venv\Scripts\Activate.ps1; `\$env:USE_HF='$hf'; `\$env:TEXT_CLASSIFIER_MODEL='$model'; `\$env:TEXT_MODE='$textMode'; `\$env:HF_ALLOW_DOWNLOADS='$allow'; `\$env:ZERO_SHOT_TEMPLATE='$zsTemplate'; `\$env:ZERO_SHOT_CANDIDATES='$zsLabels'; python -m uvicorn app:app --host ${BindHost} --port ${Port} --log-level info"
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-NoExit", "-Command", $cmd | Out-Null
        Write-Host "A new window has been opened. Leave it running. This window will now wait for health: http://${BindHost}:$Port/health" -ForegroundColor Cyan
        $deadline = (Get-Date).AddSeconds($WaitHealthSeconds)
        $healthy = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            try {
                $r = Invoke-RestMethod -Uri "http://${BindHost}:$Port/health" -TimeoutSec 3 -ErrorAction Stop
                if ($r.status -eq 'OK') { $healthy = $true; break }
            }
            catch { }
        }
        if ($healthy) {
            Write-Host "ML service is up at http://${BindHost}:$Port" -ForegroundColor Green
        }
        else {
            Write-Host "ML service did not respond to /health within $WaitHealthSeconds seconds." -ForegroundColor Yellow
            Write-Host "Please check the newly opened window for errors (package install, firewall prompt, or model download)." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Starting FastAPI (uvicorn) on ${BindHost}:$Port ..." -ForegroundColor Green
        Write-Host "Press Ctrl+C to stop" -ForegroundColor DarkGray
        python -m uvicorn app:app --host $BindHost --port $Port --log-level info
    }
}
finally {
    Pop-Location
}