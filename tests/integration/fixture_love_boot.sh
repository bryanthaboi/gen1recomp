#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
shot_root="$(mktemp -d)"
trap 'rm -rf "$shot_root"' EXIT

runner=(love .)
if command -v xvfb-run >/dev/null 2>&1; then
  runner=(xvfb-run -a love .)
fi

env \
  POKEPORT_DATA_DIR=tests/fixture_data \
  POKEPORT_BOOT_OVERWORLD=1 \
  POKEPORT_SAFE_MODE=1 \
  POKEPORT_DRIVER=tests/drivers/shots_fixture.lua \
  POKEPORT_IDENTITY=fixture-love-ci \
  POKEPORT_TOUCH=0 \
  SHOT_DIR="$shot_root" \
  "${runner[@]}"

test -s "$shot_root/fixture_overworld.png"
python3 - "$shot_root/fixture_overworld.png" <<'PY'
import sys
from PIL import Image

with Image.open(sys.argv[1]) as image:
    image.load()
    if image.width < 160 or image.height < 144:
        raise SystemExit(f"capture is too small: {image.size}")
    print(f"fixture LOVE capture: {image.size} {image.mode}")
PY

if [ "${BLESS_GOLDENS:-0}" = "1" ]; then
  python3 tools/compare_shots.py tests/goldens/shots "$shot_root" --bless
elif [ -f tests/goldens/shots/fixture_overworld.png ]; then
  python3 tools/compare_shots.py tests/goldens/shots "$shot_root"
else
  echo "fixture LOVE capture passed (no rendered golden committed yet)"
fi
