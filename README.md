# stremio-setup

Docker Compose stack for streaming Toloka.to torrents through Stremio via TorrServer, bypassing Stremio's built-in P2P engine (which can't negotiate Toloka's tracker).

```
Stremio → Comet (searches Jackett/Toloka) → jackett-throttle (rate-limits .torrent downloads) → Jackett
                ↓
comet-torrserver-bridge → TorrServer (does the actual P2P download/streaming)
```

## Services

| Service | Image | Port | Purpose |
|---|---|---|---|
| `stremio` | `tsaridas/stremio-docker` | 8080 | Stremio web UI + server |
| `jackett` | `linuxserver/jackett` | 9117 | Indexer proxy; Toloka added manually via its web UI |
| `jackett-throttle` | [`jackett-throttle-proxy`](https://github.com/serhiibuhaiov/jackett-throttle-proxy) | 9119 | Rate-limits `.torrent` downloads to 30/min so Toloka's Cloudflare doesn't ban the IP |
| `comet` | `g0ldyy/comet` | 8000 | Searches Jackett, returns Stremio-compatible stream lists |
| `torrserver` | `ghcr.io/yourok/torrserver` | 8090 | Real torrent client; turns a torrent into an HTTP stream |
| `comet-torrserver-bridge` | [`comet-torrserver-bridge-stremio-addon`](https://github.com/serhiibuhaiov/comet-torrserver-bridge-stremio-addon) | 7100 | Rewrites Comet's results into direct TorrServer play URLs |

## Setup

1. `docker compose up -d`
   - On a Linux host with an Intel iGPU (e.g. N100), add hardware transcoding for Stremio's streaming server via the override file: `docker compose -f docker-compose.yml -f docker-compose.hwaccel.yml up -d`. Requires `intel-media-va-driver-non-free` installed on the host first (`sudo apt install intel-media-va-driver-non-free vainfo`, then check `vainfo` lists the expected profiles). **Do not use this override on macOS/Docker Desktop** — `/dev/dri` doesn't exist there and the `stremio` container will fail to start.
   - `comet` waits for Jackett to generate its own API key (`jackett-config/Jackett/ServerConfig.json`) and reads it automatically at startup (`scripts/wait-for-jackett-key.sh`) — nothing to copy by hand.
2. Open `http://localhost:9117`, add the Toloka indexer manually (login/password — Jackett has no API for this, it's a one-time setup step tied to your Toloka account).
3. In Stremio, install the addons from their manifest URLs (Settings → Addons → "Search or paste link"). Each browser/account/device needs this done once — it's not shared automatically.
   - Comet direct: `http://<host>:8000/manifest.json`
   - Comet through TorrServer (recommended — actually playable): `http://<host>:7100/manifest.json`

   `<host>` depends on where the browser is relative to the machine running this stack:
   - Same machine: `localhost`
   - Another device on the LAN (phone, someone else's laptop, smart TV): the Mac's mDNS name, e.g. `serhiis-macbook-pro.local` (stable — survives DHCP lease renewals), or its current LAN IP (`ipconfig getifaddr en0`) as a fallback if mDNS/Bonjour isn't supported on that device.

## Data persistence

Bind-mounted under `~/stremio-setup-data/`, survives `docker compose down`/`up`:
- `~/stremio-setup-data/stremio` — Stremio server state
- `~/stremio-setup-data/jackett` — Jackett config + indexer credentials
- `~/stremio-setup-data/comet` — Comet's search cache (`comet.db`)
- `~/stremio-setup-data/torrserver` — TorrServer settings + torrent state

## Known fragility

- Jackett's Toloka session (cookie-based, no API) expires periodically. Symptom: searches return few/no results. Fix: re-enter login/password on the Toloka indexer in Jackett's UI.
- Cold (uncached) searches legitimately take 70-90s — this is the throttle proxy's rate limit doing its job, not a bug.
