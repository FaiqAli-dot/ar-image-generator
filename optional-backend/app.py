"""
Optional free-tier background removal API for AR Food Capture.

Uses `rembg` (open-source). Prefer on-device Vision in the iOS app;
enable this only if Vision masks are insufficient for your dishes.

Local:
  python -m venv .venv && source .venv/bin/activate
  pip install -r requirements.txt
  uvicorn app:app --host 0.0.0.0 --port 8080

Then set Info.plist BackgroundRemovalAPIBaseURL to http://<your-lan-ip>:8080
"""

from __future__ import annotations

import io
from fastapi import FastAPI, Request, Response, HTTPException
from rembg import remove

app = FastAPI(title="AR Food Background Removal", version="1.0.0")


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/v1/remove-background")
async def remove_background(request: Request):
    data = await request.body()
    if not data:
        raise HTTPException(status_code=400, detail="Empty body")
    content_type = request.headers.get("content-type", "image/jpeg")
    try:
        out = remove(data)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    return Response(content=out, media_type="image/png")
