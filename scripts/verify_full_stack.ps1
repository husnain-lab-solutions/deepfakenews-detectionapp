param(
    [string]$WebUrl = "http://localhost:5140",
    [string]$MlUrl = "",
    [string]$Email = "verify@example.com",
    [string]$Password = "P@ssw0rd!",
    [string]$SampleText = "Breaking: Scientists discover a secret device that controls the weather!",
    [string]$ImagePath = ""  # Optional: path to an image file for /predict-image; if blank a sample will be generated
)

# Full-stack verifier for DeepfakeNews application
# 1. Derive ML service URL (from appsettings if not supplied)
# 2. Check web root redirect and Swagger availability
# 3. Register (or login if already exists) and obtain JWT
# 4. Call /api/auth/me
# 5. Perform /api/predict/text and record prediction
# 6. Direct-call ML service /health & /predict-text for comparison
# 7. Summarize results

$ErrorActionPreference = 'Stop'

function Get-AppSettingsBaseUrl {
    param([string]$AppSettingsPath)
    if (-not (Test-Path $AppSettingsPath)) { return $null }
    try {
        $json = Get-Content $AppSettingsPath -Raw | ConvertFrom-Json
        return $json.PythonService.BaseUrl
    } catch { return $null }
}

Write-Host "[1/7] Resolving ML base URL..." -ForegroundColor Cyan
if (-not $MlUrl) {
    $appSettings = Join-Path (Split-Path $PSScriptRoot -Parent) 'WebApplication1/appsettings.json'
    $derived = Get-AppSettingsBaseUrl -AppSettingsPath $appSettings
    if ($derived) {
        $MlUrl = $derived.TrimEnd('/')
        Write-Host "Using ML URL from appsettings.json -> $MlUrl" -ForegroundColor Green
    } else {
        $MlUrl = 'http://127.0.0.1:8000'
        Write-Host "Fallback ML URL -> $MlUrl" -ForegroundColor Yellow
    }
}

Write-Host "[2/7] Checking web app root: $WebUrl/" -ForegroundColor Cyan
try {
    $rootResp = Invoke-WebRequest -UseBasicParsing -Uri $WebUrl/ -MaximumRedirection 5 -TimeoutSec 10
    $finalUrl = $rootResp.BaseResponse.ResponseUri.AbsoluteUri
    Write-Host "Root reachable (final URL: $finalUrl, Status: $($rootResp.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "Web root unreachable: $WebUrl/" -ForegroundColor Red; throw
}

# Optional: Swagger in dev
try {
    $sw = Invoke-WebRequest -UseBasicParsing -Uri "$WebUrl/swagger/index.html" -TimeoutSec 5
    Write-Host "Swagger UI reachable" -ForegroundColor Green
} catch { Write-Host "Swagger not reachable (expected only in Development)" -ForegroundColor Yellow }

Write-Host "[3/7] Registering or logging in user $Email ..." -ForegroundColor Cyan
$token = $null
$registerBody = @{ email = $Email; password = $Password } | ConvertTo-Json
try {
    $reg = Invoke-RestMethod -Method Post -Uri "$WebUrl/api/auth/register" -ContentType 'application/json' -Body $registerBody -TimeoutSec 15
    $token = $reg.token
    Write-Host "User registered." -ForegroundColor Green
} catch {
    Write-Host "Register failed (maybe exists) -> attempting login" -ForegroundColor Yellow
    $loginBody = @{ email = $Email; password = $Password } | ConvertTo-Json
    $login = Invoke-RestMethod -Method Post -Uri "$WebUrl/api/auth/login" -ContentType 'application/json' -Body $loginBody -TimeoutSec 15
    $token = $login.token
    Write-Host "Logged in." -ForegroundColor Green
}
if (-not $token) { throw "No JWT token obtained" }

Write-Host "[4/7] Calling /api/auth/me ..." -ForegroundColor Cyan
$me = Invoke-RestMethod -Uri "$WebUrl/api/auth/me" -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 10
Write-Host ("User Identity: {0}" -f (($me | ConvertTo-Json -Compress))) -ForegroundColor Green

Write-Host "[5/7] Predicting via Web API /api/predict/text ..." -ForegroundColor Cyan
$predBody = @{ text = $SampleText } | ConvertTo-Json -Compress
$mlRoot = Split-Path $PSScriptRoot -Parent
$mlPidPath = Join-Path $mlRoot 'ml_service/uvicorn.pid'
$mlErrLog = Join-Path $mlRoot 'ml_service/uvicorn.err.log'
$mlOutLog = Join-Path $mlRoot 'ml_service/uvicorn.out.log'
if(Test-Path $mlPidPath){
    $mlPid = Get-Content $mlPidPath | Select-Object -First 1
    $mlAlive = $false
    try { if(Get-Process -Id $mlPid -ErrorAction Stop){ $mlAlive = $true } } catch {}
    if(-not $mlAlive){
        Write-Host "ML process PID $mlPid not running before prediction attempts." -ForegroundColor Red
        if(Test-Path $mlErrLog){ Write-Host "--- uvicorn.err.log tail (60) ---" -ForegroundColor DarkYellow; Get-Content $mlErrLog -ErrorAction SilentlyContinue | Select-Object -Last 60 }
        if(Test-Path $mlOutLog){ Write-Host "--- uvicorn.out.log tail (60) ---" -ForegroundColor DarkYellow; Get-Content $mlOutLog -ErrorAction SilentlyContinue | Select-Object -Last 60 }
    }
} else {
    Write-Host "No uvicorn.pid found; ML may not be running." -ForegroundColor Yellow
}
Write-Host "Netstat port 8000 check:" -ForegroundColor Cyan
try { & netstat -ano | Select-String ":8000" } catch { Write-Host "netstat not available" -ForegroundColor Yellow }
$apiPred = $null
for($attempt=1; $attempt -le 5; $attempt++) {
    $resp = $null
    try {
        # Use Invoke-WebRequest with -SkipHttpErrorCheck so we can inspect body on non-2xx
        $resp = Invoke-WebRequest -SkipHttpErrorCheck -Method Post -Uri "$WebUrl/api/predict/text" -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $predBody -TimeoutSec 40
    } catch {
        Write-Host "Attempt $attempt transport error: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
    if($resp) {
        $status = [int]$resp.StatusCode
        $content = $resp.Content
        if($status -ge 200 -and $status -lt 300) {
            try { $apiPred = $content | ConvertFrom-Json } catch { Write-Host "Attempt $attempt JSON parse failed: $($_.Exception.Message)" -ForegroundColor Red }
            if($apiPred){ Write-Host "Attempt $attempt succeeded (status $status)." -ForegroundColor Green; break }
        } else {
            $trunc = if($content.Length -gt 500){ $content.Substring(0,500) + '...' } else { $content }
            Write-Host "Attempt $attempt non-success status $status. Body: $trunc" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "Attempt $attempt produced no response object." -ForegroundColor DarkYellow
    }
    if(-not $apiPred -and $attempt -lt 5){ Start-Sleep -Seconds ($attempt * 2) }
}
if(-not $apiPred){
    Write-Host "Web API prediction failed after retries (continuing to direct ML tests)." -ForegroundColor Red
    if(Test-Path $mlErrLog){ Write-Host "--- uvicorn.err.log tail (60) after API failure ---" -ForegroundColor DarkYellow; Get-Content $mlErrLog -ErrorAction SilentlyContinue | Select-Object -Last 60 }
    if(Test-Path $mlOutLog){ Write-Host "--- uvicorn.out.log tail (60) after API failure ---" -ForegroundColor DarkYellow; Get-Content $mlOutLog -ErrorAction SilentlyContinue | Select-Object -Last 60 }
} else {
    $apiPredJson = $apiPred | ConvertTo-Json -Compress
    Write-Host "Web API Prediction: $apiPredJson" -ForegroundColor Yellow
}

Write-Host "[6/7] Direct ML service health & raw prediction ..." -ForegroundColor Cyan
$mlHealthOk = $false
try {
    $h = Invoke-RestMethod -Uri "$MlUrl/health" -TimeoutSec 8
    if ($h.status -eq 'OK') { $mlHealthOk = $true }
    Write-Host "ML Health: $(($h | ConvertTo-Json -Compress))" -ForegroundColor Green
} catch {
    Write-Host "ML /health failed at $MlUrl" -ForegroundColor Red
}
$rawPred = $null
if ($mlHealthOk) {
    try {
        $rawPred = Invoke-RestMethod -Method Post -Uri "$MlUrl/predict-text" -ContentType 'application/json' -Body $predBody -TimeoutSec 40
        Write-Host "Raw ML Prediction: $(($rawPred | ConvertTo-Json -Compress))" -ForegroundColor Yellow
    } catch {
        Write-Host "Raw ML prediction failed." -ForegroundColor Red
    }
}

Write-Host "[6a] Optional image prediction test ..." -ForegroundColor Cyan
$imagePred = $null
if (-not $ImagePath) {
    # Auto-generate a tiny PNG sample if none provided
    $ImagePath = Join-Path $PSScriptRoot 'sample_image.png'
    if (-not (Test-Path $ImagePath)) {
        Write-Host "Generating sample image -> $ImagePath" -ForegroundColor Cyan
        # 32x32 red square PNG base64
        $pngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJ
    bWFnZVJlYWR5ccllPAAAAAlwSFlzAAAL+wAAC/sB4kT2WQAAABl0RVh0Q3JlYXRpb24gVGltZQAw
    OS8yMC8yNXW9nU0AAABHSURBVHjaYvj///9/BiAAJmBkZGBgYHjPwMDAwMiA8T8DA8O/n4GBgYEh
    ICGDl4GBgYFBgYHB/4cDIwMDA8P//38GIgAIYQAAAwCojQn2a2k2WAAAAABJRU5ErkJggg=='
        [IO.File]::WriteAllBytes($ImagePath,[Convert]::FromBase64String(($pngBase64 -replace "\s","")))
    }
}
if (Test-Path $ImagePath) {
    try {
        $form = @{ file = Get-Item -Path $ImagePath }
        $imagePred = Invoke-RestMethod -Method Post -Uri "$MlUrl/predict-image" -Form $form -TimeoutSec 40
        Write-Host "Image Prediction: $(($imagePred | ConvertTo-Json -Compress))" -ForegroundColor Yellow
    } catch {
        Write-Host "Image prediction failed." -ForegroundColor Red
    }
} else {
    Write-Host "No image path available for test." -ForegroundColor Yellow
}

Write-Host "[7/7] Summary" -ForegroundColor Cyan
$summary = [PSCustomObject]@{
    WebUrl          = $WebUrl
    MlUrl           = $MlUrl
    User            = $me.User
    JwtAcquired     = [bool]$token
    ApiPrediction   = $apiPred
    RawMlPrediction = $rawPred
    ImagePrediction = $imagePred
    MlHealthy       = $mlHealthOk
}
$summary | ConvertTo-Json -Depth 6

# Exit codes for CI: non-zero on failure
$failures = @()
if (-not $token) { $failures += 'jwt' }
if (-not $mlHealthOk) { $failures += 'ml_health' }
if (-not $apiPred) { $failures += 'api_pred' }
if ($ImagePath -and -not $imagePred) { $failures += 'image_pred' }

if ($failures.Count -gt 0) {
    Write-Host ("Failures: {0}" -f ($failures -join ',')) -ForegroundColor Red
    exit 1
} else {
    Write-Host "Done (all checks passed)." -ForegroundColor Green
    exit 0
}
