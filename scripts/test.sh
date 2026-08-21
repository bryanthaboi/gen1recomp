#!/usr/bin/env bash
# Unified test entry point (21-testing-and-ci §CI).
#
# Runs every tier that this checkout can run and exits non-zero if any of
# them fails.  The tier split is what makes that possible: T1/T2/T4 need
# nothing but the committed fixture dataset, so they run anywhere --
# including CI, which has no ROM.  T3 asserts Pokemon Red facts and needs
# data/generated/, so it is skipped automatically when the ROM has never
# been imported rather than failing the run.
#
#   scripts/test.sh                 every tier this checkout can run
#   scripts/test.sh --quick         skip the slow content tier
#   scripts/test.sh --bless         re-pin the fingerprint goldens
#   WITH_SHOTS=1 scripts/test.sh    also capture and diff golden shots
#                                   (requires love and a display)
#
# LUA overrides the interpreter (luajit here; CI installs lua5.4 too, but
# the engine targets LuaJIT/5.1 semantics so luajit is the default).

set -uo pipefail

cd "$(dirname "$0")/.."

LUA=${LUA:-luajit}
LUA54=${LUA54:-lua5.4}
BLESS=0
QUICK=0
SHOTS=${WITH_SHOTS:-0}

for arg in "$@"; do
  case "$arg" in
    --bless) BLESS=1 ;;
    --bless-shots) SHOTS=1; BLESS=1 ;;
    --quick) QUICK=1 ;;
    --help|-h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! command -v "$LUA" >/dev/null 2>&1; then
  echo "no lua interpreter '$LUA' on PATH (set LUA=...)" >&2
  exit 2
fi

# The save-directory sandbox (conf.lua reads POKEPORT_IDENTITY) is scoped
# to the shot tier, which is the only one that starts a real LOVE process
# and could write into a developer's save folder.  Exporting it for the
# whole run instead would change what SaveIO.defaultPath() returns, and the
# save-editor suite pins that to the default identity.
SANDBOX_IDENTITY="ci-$$"

FAILED=()
run_tier() {
  local label="$1"; shift
  echo ""
  echo "=============================================================="
  echo "  $label"
  echo "=============================================================="
  if "$@"; then
    echo "-- $label: PASS"
  else
    echo "-- $label: FAIL"
    FAILED+=("$label")
  fi
}

# ------- ROM-free tiers: these are what CI runs

run_tier "T0 ROM builder version routing" python3 tests/build_rom_data_cli_test.py
run_tier "T0 ROM manifest generator pin/overrides" python3 tests/rom_manifest_generator_test.py
run_tier "T0 switch CI workflow content gate" "$LUA" tests/switch_ci_workflows_test.lua
run_tier "T0 switch transfer docs gate" "$LUA" tests/switch_transfer_docs_test.lua
# NX Blue/Yellow asset overlay: ROM-free, must run on every checkout so a
# Sound.lua / overlay regression is not gated only on switch-changes paths.
run_tier "T0 NX asset overlay fallback" "$LUA" tests/engine/assets_version_fallback_test.lua
run_tier "T0 NX generated-path static guard" "$LUA" tests/engine/nx_generated_guard_test.lua
run_tier "T0 NX Yellow/Blue boot (dynamic paths)" "$LUA" tests/engine/nx_yellow_boot_test.lua
run_tier "T0 NX Gold cache load (maps.lua prefix)" "$LUA" tests/engine/cache_fs_gold_nx_load_test.lua
run_tier "T0 touch-controls pad cursor" "$LUA" tests/engine/touch_controls_pad_cursor_test.lua
run_tier "T1/T2 engine invariants + parity gates" "$LUA" tests/run_engine.lua
run_tier "T2 Gen 2 fixture suites" "$LUA" tests/run_gen2.lua
run_tier "T2 standalone regressions" "$LUA" tests/run_standalone.lua
run_tier "T4 mod-SDK" "$LUA" tests/run_modkit.lua
run_tier "T4 title checkpoint cold restart" \
  bash tests/integration/title_checkpoint_cold_start.sh
run_tier "T4 save backup cold restart" \
  bash tests/integration/save_restart_recovery.sh

# The modded-link desync suite (symmetric mod, handshake fail-closed,
# extra-bag round trip) is ROM-free and runs inside the T4 tier above, as
# tests/modkit/cases/link_desync.lua.
#
# tests/run_link_tests.lua is a different matter: it calls Data:load() at
# :27 and so needs data/generated/.  It is grouped with the content tier
# until that bootstrap can take an injected dataset.
# ------- content tier: only meaningful with an imported ROM


# tests/run_tests.lua is expected to be clean.  It used to carry two stale
# chip-audio assertions on the allowlist below (Pikachu cry WAV exists /
# low-health alarm sfx extracted); both have since been fixed, so the
# baseline is zero and any failure fails the tier.  Keep the allowlist
# mechanism rather than ignoring the exit code -- that would hide every
# future content regression.
KNOWN_CONTENT_FAILURES=0
KNOWN_CONTENT_LINES=""

run_content_behavior() {
  local out
  out=$("$LUA" tests/run_tests.lua 2>&1)
  local count
  count=$(printf '%s\n' "$out" | grep -c '^FAIL ' || true)
  local lines
  lines=$(printf '%s\n' "$out" | grep '^FAIL ' | sort)

  if [ "$count" -eq "$KNOWN_CONTENT_FAILURES" ] \
     && [ "$lines" = "$(printf '%s\n' "$KNOWN_CONTENT_LINES" | sort)" ]; then
    printf '%s\n' "$out" | tail -3
    if [ "$KNOWN_CONTENT_FAILURES" -gt 0 ]; then
      echo "(the $KNOWN_CONTENT_FAILURES known stale assertions, unchanged)"
    fi
    return 0
  fi

  printf '%s\n' "$out" | grep '^FAIL ' || true
  printf '%s\n' "$out" | tail -2
  echo "expected exactly $KNOWN_CONTENT_FAILURES known failures; got $count"
  return 1
}

if [ -f data/generated/maps.lua ]; then
  if [ "$QUICK" = "1" ]; then
    echo ""
    echo "-- T3 content: skipped (--quick)"
  else
    run_tier "T3 content behavior (Red)" run_content_behavior
    # The save editor ships inside every build (the launcher's Edit button on
    # a save row opens it), so its panel suites run in CI rather than by hand.
    run_tier "T3 save editor" "$LUA" tests/run_save_editor_tests.lua
    run_tier "T3 save editor: boxes + items" "$LUA" tests/save_editor_task6_tests.lua
    run_tier "T3 save editor: events + dex" "$LUA" tests/save_editor_task7_tests.lua
    run_tier "T3 save editor: map browser" "$LUA" tests/save_editor_task8_tests.lua
    run_tier "T3 save editor: mod awareness" "$LUA" tests/save_editor_mod_tests.lua
    run_tier "T3 save editor: gold / gen2" "$LUA" tests/save_editor_gen2_tests.lua
    run_tier "T3 save editor: wheel scrolling" "$LUA" tests/save_editor_wheel_bug595_test.lua
    run_tier "T3 save editor: pad / NX input" "$LUA" tests/save_editor_pad_input_test.lua
    run_tier "T5 link (loopback lockstep)" "$LUA" tests/run_link_tests.lua
    # The oversize-save vendor oracle (tests/save_oversize_vendor_test.lua)
    # cross-checks the launcher's footer-truncation import against the
    # INDEPENDENT PKHeX-derived gen1lib codec, which cannot run under luajit
    # (native 5.3+ operators).  Needs a stock Lua 5.3/5.4; skip when absent.
    if command -v "$LUA54" >/dev/null 2>&1; then
      run_tier "T3 save oversize vendor oracle" "$LUA54" tests/save_oversize_vendor_test.lua
    else
      echo ""
      echo "-- T3 save oversize vendor oracle: skipped (no '$LUA54' on PATH; set LUA54=...)"
    fi
  fi
else
  echo ""
  echo "-- T3 content + run_link_tests: skipped (no data/generated/ --"
  echo "   import a ROM to run them; the modded-link cases ran in T4)"
fi

# ------- golden screenshots: needs love + a display

if [ "$SHOTS" = "1" ]; then
  if ! command -v love >/dev/null 2>&1; then
    echo ""
    echo "-- T5 shots: love is not on PATH but WITH_SHOTS was requested"
    FAILED+=("T5 shots (love missing)")
  else
    run_tier "T5 fixture LOVE boot + capture" \
      env BLESS_GOLDENS="$BLESS" bash tests/integration/fixture_love_boot.sh
  fi
fi

# ------- fingerprint blessing

if [ "$BLESS" = "1" ] && [ "$SHOTS" != "1" ]; then
  echo ""
  echo "re-pinning fingerprint goldens (deliberate parity change -- record it"
  echo "in docs/known-differences.md or docs/new-features.md)"
  "$LUA" tests/bless_fingerprints.lua || FAILED+=("fingerprint bless")
fi

# ------- verdict

echo ""
echo "=============================================================="
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "  ALL TIERS PASSED"
  echo "=============================================================="
  exit 0
fi

echo "  ${#FAILED[@]} TIER(S) FAILED"
for tier in "${FAILED[@]}"; do echo "    - $tier"; done
echo "=============================================================="
exit 1
