# Deepfake News Detection App (30% Milestone)

This milestone delivers a functional backend API with authentication, prediction endpoints integrated with a Python FastAPI microservice, history persistence in SQLite, and Swagger docs. A minimal ML microservice is included with optional Hugging Face models.

## Architecture

- Frontend (to be added next): Blazor or React can call the backend APIs.
- Backend: ASP.NET Core (net9.0)
  - Auth: JWT using ASP.NET Core Identity + SQLite
  - Endpoints:
    - POST /api/auth/register
    - POST /api/auth/login
    - POST /api/predict/text (auth)
    - POST /api/predict/image (multipart, auth)
    - GET  /api/history (auth)
  - Swagger UI for exploration in Development
- ML Microservice: Python + FastAPI `/ml_service` with:
  - GET /health
  - POST /predict-text
  - POST /predict-image
  - Optional Hugging Face models, with fallbacks if Transformers/Torch unavailable

## Prerequisites

- .NET SDK 9.0
- Python 3.10+

## Run the ML microservice

```powershell
# In the ml_service folder
# Option A: Use helper script (recommended)
./run_ml.ps1 -NewWindow -UseHF -Model "<huggingface-model-id>" -TextMode classifier -AllowDownloads

# Example using a DistilBERT fake-news classifier from Hugging Face
# ./run_ml.ps1 -NewWindow -UseHF -Model "mrm8488/distilroberta-finetuned-fake-news" -TextMode classifier -AllowDownloads

# Option B: Manual setup
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
# Optional env vars for model selection
# $env:USE_HF = "1"                      # enable transformers-based models
# $env:TEXT_CLASSIFIER_MODEL = "<id>"    # e.g., a DistilBERT fake-news classifier
# $env:TEXT_MODE = "classifier"          # classifier | auto | heuristic
# $env:HF_ALLOW_DOWNLOADS = "1"          # allow downloading models if not cached
uvicorn app:app --host 0.0.0.0 --port 8000
```

Verify health:

```powershell
curl http://localhost:8000/health
```

## Configure and run the .NET backend

1. Edit `WebApplication1/appsettings.json` and replace `Jwt:Key` with a long random secret (at least 64 chars).
2. Ensure `PythonService:BaseUrl` matches the microservice URL (default `http://localhost:8000`).

Run the backend:

```powershell
# From the solution root or WebApplication1 folder
dotnet restore
dotnet run --project .\WebApplication1\WebApplication1.csproj
```

The backend will create `deepfakenews.db` (SQLite) on first run. Swagger UI is enabled in Development at:

```
https://localhost:****/swagger
```

## Quick test workflow

1. Register a user

```powershell
$token = (
  Invoke-RestMethod -Uri https://localhost:5001/api/auth/register -Method Post -ContentType 'application/json' -Body '{"email":"test@example.com","password":"P@ssw0rd!"}'
).token
```

2. Predict text

```powershell
Invoke-RestMethod -Uri https://localhost:5001/api/predict/text -Headers @{ Authorization = "Bearer $token" } -Method Post -ContentType 'application/json' -Body '{"text":"Breaking: shocking news sample"}'
```

3. Predict image

```powershell
Invoke-RestMethod -Uri https://localhost:5001/api/predict/image -Headers @{ Authorization = "Bearer $token" } -Method Post -Form @{ file = Get-Item .\sample.jpg }
```

4. View history

```powershell
Invoke-RestMethod -Uri https://localhost:5001/api/history -Headers @{ Authorization = "Bearer $token" } -Method Get
```

## Notes and next steps

- Add a Blazor front-end: login/register, upload, results, and history pages.
- Replace `EnsureCreated()` with EF Core Migrations for production:

```powershell
# Optional: create migrations
Add-Migration Init -Project WebApplication1
Update-Database -Project WebApplication1
```

- Extend the Python service with proper models and caching; add `/predict-video` using frame sampling.
- Add automated tests: xUnit for backend, pytest for microservice.
- Harden security: input validation, file type checks, CORS per environment, HTTPS only in production.
