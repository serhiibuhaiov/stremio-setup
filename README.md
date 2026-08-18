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
| `db-viewer` | `coleifer/sqlite-web` | 8091 | Browse/edit Comet's `comet.db` cache directly — useful for clearing stale search results |
| `caddy` | `caddy:2-alpine` | 80 | Reverse proxy — lets you reach every service by a friendly `*.lan` hostname instead of `<host>:<port>` (see below) |

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
   - Another device on the LAN (phone, someone else's laptop, smart TV): the host's mDNS name, or its current LAN IP as a fallback if mDNS/Bonjour isn't supported on that device.
   - Or skip juggling hosts/ports entirely and use `http://comet-torrserver-bridge.lan/manifest.json` — see [Friendly local hostnames](#friendly-local-hostnames-optional) below.

## Friendly local hostnames (optional)

`caddy` reverse-proxies each service to a `*.lan` hostname on port 80, so you don't have to remember/type ports:

| Hostname | Proxies to |
|---|---|
| `http://stremio.lan` | Stremio web UI |
| `http://jackett.lan` | Jackett indexer admin |
| `http://torrserver.lan` | TorrServer admin UI |
| `http://comet.lan` | Comet |
| `http://comet-torrserver-bridge.lan` | Comet-TorrServer bridge (the addon you install in Stremio) |
| `http://comet-dbviewer.lan` | Comet's SQLite DB viewer |

These are plain HTTP, LAN-only — Caddy is deliberately configured (`http://` prefix in the [Caddyfile](Caddyfile)) to skip automatic HTTPS, since Let's Encrypt can't issue certs for a private `.lan` name anyway.

For these hostnames to resolve, add a host entry for each one to your router's local DNS, pointing at the mini PC's LAN IP. On a GL.iNet router: Admin Panel → **DNS → Edit Hosts** → add each hostname above (without `http://`) → that IP. Once added, every device using the router as DNS (the default) can reach these without any per-device setup.

## Data persistence

Bind-mounted under `~/stremio-setup-data/`, survives `docker compose down`/`up`:
- `~/stremio-setup-data/stremio` — Stremio server state
- `~/stremio-setup-data/jackett` — Jackett config + indexer credentials
- `~/stremio-setup-data/comet` — Comet's search cache (`comet.db`)
- `~/stremio-setup-data/torrserver` — TorrServer settings + torrent state
- `~/stremio-setup-data/caddy` — Caddy's internal state (autosave config; no certs needed since HTTPS is disabled for these hosts)

## Known fragility

- Jackett's Toloka session (cookie-based, no API) expires periodically. Symptom: searches return few/no results. Fix: re-enter login/password on the Toloka indexer in Jackett's UI.
- Cold (uncached) searches legitimately take 70-90s — this is the throttle proxy's rate limit doing its job, not a bug.
- **Docker Desktop on macOS can hang under real BitTorrent traffic.** Symptom: `docker` commands / `docker compose ps` start failing with `500 Internal Server Error`, every container becomes unreachable, right around when TorrServer starts actually downloading (not on search/browse — only once real P2P traffic starts). Confirmed root cause via the VM's kernel log (`~/Library/Containers/com.docker.docker/Data/log/vm/console.log`): `virtio_net virtio0 eth0: NETDEV WATCHDOG: transmit queue 0 timed out` — Docker Desktop's gVisor network stack deadlocks under BitTorrent's UDP-heavy traffic pattern (DHT, many concurrent peers). Fixed by enabling **Docker Desktop → Settings → Resources → Network → "Use kernel networking for UDP"** (routes UDP through a more robust path; incompatible with some VPN clients, not an issue here). If it hangs again anyway: `pgrep -fl com.docker` to find the wedged `com.docker.backend`/`com.docker.virtualization` PIDs, `kill -9` them, then `open -a Docker` — a plain Docker Desktop restart from the UI can silently reattach to the same wedged process instead of doing a cold start.
