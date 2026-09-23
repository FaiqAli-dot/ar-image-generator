# Optional Background Removal Backend

On-device Apple Vision (`VNGenerateForegroundInstanceMaskRequest`) is the default.
Use this backend only if Vision quality is insufficient for your dishes.

> **Phase 2 note:** Object upload / permanent AR URLs live in [`../backend/`](../backend/) (Node/Express).
> This folder remains the optional **rembg** cutout helper only.

## API

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/health` | — | `{ "ok": true }` |
| POST | `/v1/remove-background` | raw JPEG/PNG bytes (`Content-Type: image/jpeg`) | PNG with alpha |

## One-command local run

```bash
cd optional-backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8080
```

Point the iOS app at it by setting `BackgroundRemovalAPIBaseURL` in
`ARFoodCapture/Info.plist` to `http://YOUR_MAC_LAN_IP:8080` (device and Mac on same network).

## Free-tier deploy (Render example)

1. Create a new Web Service from this `optional-backend` folder.
2. Build: `pip install -r requirements.txt`
3. Start: `uvicorn app:app --host 0.0.0.0 --port $PORT`
4. Set `BackgroundRemovalAPIBaseURL` to the Render HTTPS URL (no trailing slash).

### Notes

- First request downloads the rembg model (~170MB) — expect a cold start.
- Free tiers sleep; keep Vision as primary so the app works offline.
- For Phase 2 object persistence + QR / remote AR, use [`../backend/`](../backend/).
