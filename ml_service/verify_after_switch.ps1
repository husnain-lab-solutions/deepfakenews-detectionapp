param(
    [string]$WatcherJobName = "SwitchWatcher",
    [string]$Host = "127.0.0.1",
    [int]$Port = 8000
)

$ErrorActionPreference = 'Continue'
Push-Location $PSScriptRoot
try {
    Write-Host "Waiting for watcher job '$WatcherJobName' to finish switching..." -ForegroundColor Cyan
    $wj = Get-Job -Name $WatcherJobName -ErrorAction SilentlyContinue
    if ($wj) { Wait-Job -Id $wj.Id | Out-Null }

    $healthUrl = "http://$Host:$Port/health"
    for ($i=0; $i -lt 30; $i++) {
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 3
            if ($r.StatusCode -eq 200) { Write-Host "Health OK at $healthUrl" -ForegroundColor Green; break }
        } catch { Start-Sleep -Seconds 2 }
        Start-Sleep -Seconds 2
    }

    try {
        $payload = @{ text = 'Breaking: miracle cure discovered in 24 hours!' } | ConvertTo-Json -Compress
        $pred = Invoke-RestMethod -Method Post -Uri ("http://{0}:{1}/predict-text" -f $Host,$Port) -Body $payload -ContentType 'application/json'
        Write-Host ("Prediction response: {0}" -f ($pred | ConvertTo-Json -Compress)) -ForegroundColor Yellow
    } catch {
        Write-Host "Prediction check failed: $_" -ForegroundColor Red
    }
}
finally {
    Pop-Location
}