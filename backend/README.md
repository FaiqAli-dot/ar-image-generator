# AR Food Object API (Phase 2 + GLB import)

Node/Express REST API that persists **real transparent photographic views** + metadata and returns a permanent `arUrl` for QR / remote AR.

**GLB dual-output** adds: owner import UI, gltf-transform optimization, browser `<model-viewer>` menu, optional AR hooks, and synthetic 16/72-view renders from the same GLB. Photo upload path is unchanged.

Docs: [`docs/glb-import-and-browser-3d.md`](../docs/glb-import-and-browser-3d.md).

This is the product backend. The sibling [`optional-backend/`](../optional-backend/) remains the optional **rembg** background-removal helper only.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/health` | Liveness |
| `GET` | `/owner` | Owner GLB import / publish UI |
| `POST` | `/api/objects` | Multipart upload (`metadata` JSON + `images` PNGs + optional `thumbnail`) |
| `GET` | `/api/objects/:id` | Object metadata (FoodObject-compatible) + URLs |
| `GET` | `/api/objects/:id/images/:filename` | Transparent view PNG |
| `GET` | `/api/objects/:id/thumbnail` | Thumbnail PNG |
| `GET` | `/api/objects/:id/model/:variant` | `original` / `optimized` / `optimized-mobile` GLB |
| `GET` | `/api/objects/:id/renders/:16\|72/:file` | Synthetic view PNG or `manifest.json` |
| `POST` | `/api/glb/import` | Upload + validate GLB → draft |
| `POST` | `/api/glb/drafts/:id/process` | Optimize + render 16/72 (cached) |
| `POST` | `/api/glb/drafts/:id/publish` | Persist hybrid object |
| `GET` | `/ar/:id` | Customer menu (model-viewer and/or photo spin + deep link) |
| `GET` | `/dev/compare/:id` | Dev dual-output comparison UI |
| `GET` | `/capture` | Capture QR landing → `arfood://capture` |

### `POST /api/objects` metadata JSON

```json
{
  "name": "Demo Burger",
  "widthCm": 12,
  "description": "Optional",
  "isDemo": false,
  "views": [
    { "azimuth": 0, "elevation": 0, "image": "view_000.png", "distance": 0.45 }
  ]
}
```

Files: field `images` (one part per PNG, filename must match `views[].image`), optional `thumbnail`.

Response includes `id`, `arUrl`, `apiUrl`, `deepLink`.

## Local run

```bash
cd backend
npm install
npm start
# → http://localhost:3000
```

Tests:

```bash
npm test
```

## Env vars

| Var | Default | Meaning |
|-----|---------|---------|
| `PORT` | `3000` | Listen port |
| `PUBLIC_BASE_URL` | _(from request host)_ | Canonical HTTPS origin for permanent `arUrl` (set this in production) |
| `DATA_DIR` / `OBJECTS_DIR` | `./data` | Filesystem object store |
| `MAX_IMAGE_BYTES` | `8388608` | Per-file image limit |
| `MAX_GLB_BYTES` | `83886080` | Max GLB upload (~80 MB) |
| `RENDER_RES` | `512` | Synthetic view square resolution |
| `BLENDER` | _(unset)_ | Optional Blender 4.2+ binary; else Playwright/three.js |
| `MAX_VIEWS` | `120` | Max views per object |

## Deploy (Render example)

1. New **Web Service**, root directory `backend`
2. Build: `npm install`
3. Start: `npm start`
4. Set `PUBLIC_BASE_URL=https://YOUR-SERVICE.onrender.com` (no trailing slash)
5. Attach a persistent disk to `/opt/render/project/src/data` (or set `DATA_DIR` to the mount) so uploads survive restarts

Railway / Fly.io: same Node start command; set `PUBLIC_BASE_URL` to the public HTTPS URL.

### Docker

```bash
docker build -t ar-food-api ./backend
docker run -p 3000:3000 -e PUBLIC_BASE_URL=https://example.com -v arfood-data:/app/data ar-food-api
```

## Security (MVP)

- Validates object IDs, sanitizes image filenames (no path traversal)
- Size / view-count limits
- No auth yet (do not expose write endpoints publicly without a network control if abused)

## Customer AR flow

1. Restaurant uploads → receives `arUrl` = `{PUBLIC_BASE_URL}/ar/{id}`
2. App shows QR for that HTTPS URL (works off localhost when deployed)
3. Customer opens page → deep link `arfood://object/{id}` → native photographic AR viewer loads remote views
