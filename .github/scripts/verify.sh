#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
for arg in "$@"; do
  if [ "$arg" != "--strict" ]; then
    echo "usage: bun run verify [--strict]" >&2
    exit 1
  fi
done
bun test:contracts
bash .github/scripts/selftest-swift-packages-exit.sh
bash .github/scripts/macos-release-launch-smoke.test.sh
python3 -B -m unittest discover -s docs/acceptance/macos-parity -p '*_test.py'
python3 -B docs/acceptance/macos-parity/parity_loop.py validate
python3 -B docs/acceptance/macos-parity/audit.py check
bash .github/scripts/render-macos-icon.sh
bun run test
echo "VERDICT: PASS"
