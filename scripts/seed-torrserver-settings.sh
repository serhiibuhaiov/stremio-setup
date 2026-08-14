#!/bin/sh
set -e

SETTINGS_FILE="${TS_CONF_PATH:-/opt/ts/config}/settings.json"
TEMPLATE="/torrserver-settings.template.json"

if [ ! -f "$SETTINGS_FILE" ]; then
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  cp "$TEMPLATE" "$SETTINGS_FILE"
  echo "seeded torrserver settings.json with tuned defaults (CacheSize=1GB, PreloadCache=15%)"
fi

exec /docker-entrypoint.sh
