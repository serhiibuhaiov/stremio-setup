#!/bin/sh
set -e

CONFIG_FILE="/jackett-config/Jackett/ServerConfig.json"
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

echo "got jackett API key, starting comet"
export JACKETT_API_KEY="$KEY"
exec python -m comet.main
