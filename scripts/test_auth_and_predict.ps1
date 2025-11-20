# Login and predict helpers for DeepfakeNews app
$ErrorActionPreference = 'Stop'

$base = 'http://localhost:5140'
$email = 'test@example.com'
$password = 'P@ssw0rd!'
$text = 'World cup 2023 is won by India'

Write-Host 'Logging in...' -ForegroundColor Cyan
$loginBody = @{ email = $email; password = $password } | ConvertTo-Json
$login = Invoke-RestMethod -Method Post -Uri "$base/api/auth/login" -ContentType 'application/json' -Body $loginBody
$token = $login.token
if (-not $token) { throw 'No token returned from login' }
Write-Host 'Token acquired' -ForegroundColor Green

Write-Host 'Calling /api/auth/me...' -ForegroundColor Cyan
$me = Invoke-RestMethod -Method Get -Uri "$base/api/auth/me" -Headers @{ Authorization = "Bearer $token" }
$me | ConvertTo-Json

Write-Host 'Predicting text...' -ForegroundColor Cyan
$predBody = @{ text = $text } | ConvertTo-Json
$pred = Invoke-RestMethod -Method Post -Uri "$base/api/predict/text" -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $predBody
$pred | ConvertTo-Json

Write-Host 'Loading history...' -ForegroundColor Cyan
$history = Invoke-RestMethod -Method Get -Uri "$base/api/history" -Headers @{ Authorization = "Bearer $token" }
$history | ConvertTo-Json