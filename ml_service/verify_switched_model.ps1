param(
    [string]$WatcherJob = "SwitchWatcher",
    [int]$Port = 8000,
    [string]$BindHost = "127.0.0.1",
    [int]$HealthWaitSeconds = 60
)

$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
try {
    $job = Get-Job -Name $WatcherJob -ErrorAction SilentlyContinue
    if ($job) {
        Write-Host ("Waiting for watcher job '{0}' to complete..." -f $WatcherJob) -ForegroundColor Cyan
        Wait-Job -Name $WatcherJob | Out-Null
        try { Receive-Job -Name $WatcherJob -Keep | Out-Host } catch {}
    } else {
        Write-Host "Watcher job not found. Proceeding to health check anyway..." -ForegroundColor Yellow
    }

    $deadline = (Get-Date).AddSeconds($HealthWaitSeconds)
    $healthy = $false
    while((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        try {
            $r = Invoke-RestMethod -Uri ("http://{0}:{1}/health" -f $BindHost, $Port) -TimeoutSec 3 -ErrorAction Stop
            if ($r.status -eq 'OK') { $healthy = $true; break }
        } catch {}
    }

    if (-not $healthy) {
        Write-Host ("Service did not report healthy at http://{0}:{1}/health within {2}s" -f $BindHost, $Port, $HealthWaitSeconds) -ForegroundColor Red
        exit 1
    }

    Write-Host ("Service healthy at http://{0}:{1}/health" -f $BindHost, $Port) -ForegroundColor Green

    # Sample prediction
    $sample = @{ text = "Breaking: miracle cure endorsed by celebrity guarantees instant results" }
    try {
        $resp = Invoke-RestMethod -Method Post -Uri ("http://{0}:{1}/predict-text" -f $BindHost, $Port) -ContentType 'application/json' -Body ($sample | ConvertTo-Json -Depth 3)
        Write-Host "Sample prediction:" -ForegroundColor Cyan
        $resp | ConvertTo-Json -Depth 5 | Out-Host
    } catch {
        Write-Host "Prediction request failed. Please check service logs." -ForegroundColor Red
        exit 1
    }
}
finally {
    Pop-Location
}