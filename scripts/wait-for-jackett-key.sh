#!/bin/sh
set -e

CONFIG_FILE="/jackett-config/Jackett/ServerConfig.json"
JACKETT_HEALTH_URL="http://jackett-throttle:9119/health"
ELAPSED=0

echo "waiting for jackett to generate its API key..."
while true; do
  KEY=$(python3 -c "
import json
try:
    with open('$CONFIG_FILE') as f:
        print(json.load(f).get('APIKey') or '')
except Exception:
    print('')
" 2>/dev/null)

  if [ -n "$KEY" ]; then
    break
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
  if [ $((ELAPSED % 30)) -eq 0 ]; then
    echo "still waiting for jackett's API key (${ELAPSED}s)... is the jackett container up?"
  fi
done

echo "got jackett API key, waiting for jackett to accept requests..."
ELAPSED=0
while ! python3 -c "
import sys
import urllib.request
try:
    with urllib.request.urlopen('$JACKETT_HEALTH_URL', timeout=2) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null; do
  sleep 1
  ELAPSED=$((ELAPSED + 1))
  if [ $((ELAPSED % 15)) -eq 0 ]; then
    echo "still waiting for jackett to respond on $JACKETT_HEALTH_URL (${ELAPSED}s)..."
  fi
done

echo "jackett is ready, starting comet"
export JACKETT_API_KEY="$KEY"
exec python -m comet.main
