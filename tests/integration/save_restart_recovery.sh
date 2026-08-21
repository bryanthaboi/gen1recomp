#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

"${LUA:-luajit}" tests/integration/save_restart_recovery.lua write "$test_root"
"${LUA:-luajit}" tests/integration/save_restart_recovery.lua recover "$test_root"
