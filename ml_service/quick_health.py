import os
from fastapi import FastAPI
import uvicorn

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "OK"}

if __name__ == "__main__":
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8000"))
    print(f"Starting minimal health server on {host}:{port}")
    uvicorn.run("quick_health:app", host=host, port=port, log_level="info")
