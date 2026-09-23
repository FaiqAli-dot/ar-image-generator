# iOS API base URL & device setup (Phase 2)

## Configure the object API URL

The app reads **`ARFoodAPIBaseURL`** from `Info.plist`.

| Build | Behavior |
|-------|----------|
| **Debug** | If plist is empty, defaults to `http://127.0.0.1:3000` for simulator. On a **physical iPhone**, override to your Mac’s LAN IP (e.g. `http://192.168.1.20:3000`) via Capture Debug, or set the plist before Run. |
| **Release** | No localhost default. You **must** set `ARFoodAPIBaseURL` to your deployed HTTPS origin (e.g. `https://ar-food-api.onrender.com`). |

### Info.plist

```xml
<key>ARFoodAPIBaseURL</key>
<string>https://YOUR-SERVICE.onrender.com</string>
```

No trailing slash. Do not commit secrets (there are none required for MVP).

### Runtime override (DEBUG sheet)

Home → tap version `v2.0.0` five times → **CAPTURE DEBUG** → **API base URL** → Save override. Stored in `UserDefaults` (`ARFoodAPIBaseURLOverride`).

`NSAppTransportSecurity` → `NSAllowsLocalNetworking` is enabled for LAN HTTP during development. Production should use HTTPS.

## Xcode signing (physical iPhone)

1. Open `ARFoodCapture/ARFoodCapture.xcodeproj`
2. Target **ARFoodCapture** → **Signing & Capabilities**
3. Enable **Automatically manage signing**, pick your Team
4. Change Bundle ID if needed (`com.arfood.capture`)
5. Connect iPhone, enable **Developer Mode**, trust the computer & developer cert
6. Run on device (ARKit + camera require a real iPhone)

## Deep links

| URL | Action |
|-----|--------|
| `arfood://capture` | Opens guided capture (Capture QR minimum path) |
| `arfood://object/{id}` | Downloads remote object (if needed) → photographic AR |
| `https://API/ar/{id}` | Permanent customer link / QR target; landing page opens the deep link |

URL scheme `arfood` is registered in `Info.plist`.

## Background removal (optional)

`BackgroundRemovalAPIBaseURL` still points at the Python rembg helper in `optional-backend/` if Vision masks are insufficient. Independent from the Phase 2 object API.
