#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SOURCE=${1:?usage: sync-from-web.sh /absolute/path/to/compass-calendar}
SOURCE=$(cd "$SOURCE" && pwd)
if [ -n "$(git -C "$SOURCE" status --porcelain)" ]; then
  echo "Source checkout must be clean so WEB_SOURCE_REVISION identifies the exported tree." >&2
  exit 1
fi
export COMPASS_MACOS_DIR="$ROOT/apps/calendar-macos"
cd "$SOURCE"
bun cli contracts:swift
bun cli desktop:export
bun cli contracts:swift --check
bun cli desktop:export --check
git rev-parse HEAD > "$ROOT/WEB_SOURCE_REVISION"
