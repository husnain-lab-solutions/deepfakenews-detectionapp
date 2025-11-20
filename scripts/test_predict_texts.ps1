param(
    [string]$BaseUrl = "http://127.0.0.1:8000"
)

$tests = @(
    "The city council approved the 2025 budget after a public hearing on Tuesday.",
    "WHO reported a 3% decline in global influenza cases this quarter.",
    "NASA confirmed the launch window opens at 13:45 UTC on November 18, 2025.",
    "The university announced a new scholarship program for STEM students.",
    "The central bank kept interest rates unchanged at 5.25%.",
    "Breaking: Scientists discover a secret device that controls the weather!",
    "Exclusive: Celebrity admits shocking plan to buy an entire country!",
    "Shocking new cure reverses aging in 24 hours, experts stunned!",
    "This hidden trick lets you double your money overnight—banks hate it!",
    "You won’t believe how this team defeated every world champion in one day!",
    "In 2024, the underdog won the national championship by a record margin.",
    "A leaked memo allegedly shows a plan to change election results.",
    "Analysts predict a 40% rise in migration in 2026 due to climate factors.",
    "The minister said the project was completed under budget and ahead of schedule."
)

Write-Host "Health check -> $BaseUrl/health" -ForegroundColor Cyan
try {
    $h = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 5 -ErrorAction Stop
    Write-Host ("Health: {0}" -f ($h | ConvertTo-Json -Compress)) -ForegroundColor Green
}
catch {
    Write-Host "Health check failed. Ensure ML service is running at $BaseUrl" -ForegroundColor Red
    exit 1
}

foreach ($t in $tests) {
    $payload = @{ text = $t } | ConvertTo-Json -Compress
    try {
        $res = Invoke-RestMethod -Method Post -Uri "$BaseUrl/predict-text" -ContentType 'application/json' -Body $payload -TimeoutSec 20
        $label = $res.label
        $conf = [math]::Round([double]$res.confidence, 3)
        Write-Host "[label=$label conf=$conf] $t" -ForegroundColor Yellow
    }
    catch {
        Write-Host "Request failed for: $t" -ForegroundColor Red
    }
}
