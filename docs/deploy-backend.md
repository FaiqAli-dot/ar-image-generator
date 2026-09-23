# Deploy the Phase 2 object API

The photographic object backend lives in [`backend/`](../backend/). It stores real transparent PNGs on disk and returns a permanent HTTPS `arUrl` for QR codes.

## Recommended: Render

1. Push this repo to GitHub.
2. Render → **New Web Service** → connect the repo.
3. Settings:
   - **Root Directory:** `backend`
   - **Runtime:** Node
   - **Build Command:** `npm install`
   - **Start Command:** `npm start`
4. Environment:
   - `PUBLIC_BASE_URL` = `https://YOUR-SERVICE.onrender.com` (no trailing slash)
   - `PORT` is provided by Render
5. **Persistent disk** (important): mount at `/opt/render/project/src/data` (or set `DATA_DIR` to your mount path). Without a disk, free-tier restarts wipe uploads.
6. After deploy, open `https://YOUR-SERVICE.onrender.com/health` → `{ "ok": true }`.

## Railway

1. New project from repo, set root to `backend`.
2. Start: `npm start`
3. Set `PUBLIC_BASE_URL` to the Railway HTTPS domain.
4. Attach a volume for `DATA_DIR`.

## Fly.io

```bash
cd backend
fly launch
fly volumes create arfood_data --size 1
# set PUBLIC_BASE_URL in fly secrets / app config
fly deploy
```

## Docker

```bash
docker build -t ar-food-api ./backend
docker run -p 3000:3000 \
  -e PUBLIC_BASE_URL=https://your.domain \
  -v arfood-data:/app/data \
  ar-food-api
```

## After deploy — point the iOS app

Set `ARFoodAPIBaseURL` in `ARFoodCapture/Info.plist` (or Debug override) to the same HTTPS origin as `PUBLIC_BASE_URL`. See [ios-api-config.md](ios-api-config.md).

## Optional rembg cutout service

[`optional-backend/`](../optional-backend/) is unchanged: Python rembg for background removal only. It is **not** the object persistence API.
