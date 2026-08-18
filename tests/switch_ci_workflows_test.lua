-- Content gate for Switch CI iOS-parity (SWCI-01..09).
-- Self-contained: luajit tests/switch_ci_workflows_test.lua

local T = require("tests.harness")
local check = T.check

local function read(path)
  local f, err = io.open(path, "r")
  if not f then error("cannot read " .. path .. ": " .. tostring(err)) end
  local s = f:read("*a")
  f:close()
  return s
end

local function mustContain(body, needle, label)
  check(body:find(needle, 1, true) ~= nil,
    label .. " must contain " .. string.format("%q", needle))
end

local function mustNotContain(body, needle, label)
  check(body:find(needle, 1, true) == nil,
    label .. " must not contain " .. string.format("%q", needle))
end

-- Exact path regex contract (SWCI-01 / 4A + SWFIX-03 test path).
-- Also gates the NX runtime modules and the NX engine suites so an NX
-- runtime regression cannot slip past switch-selftest / switch-build.
local SWITCH_PATH_REGEX =
  [[^(scripts/build_switch\.sh$|scripts/switch/|docs/switch-.*\.md$|tests/switch_ci_workflows_test\.lua$|tests/switch_transfer_docs_test\.lua$|\.github/workflows/(ci|release|switch-artifact-comment)\.yml$|src/core/(NxAssetOverlay|Platform|GameVersion)\.lua$|src/import/CacheFs\.lua$|tests/engine/(assets_version_fallback|nx_generated_guard|nx_yellow_boot|switch_diagnostics|cache_fs_gold_nx_load)_test\.lua$|tests/engine/platform_nx)]]

local ci = read(".github/workflows/ci.yml")
local release = read(".github/workflows/release.yml")
local comment_wf = read(".github/workflows/switch-artifact-comment.yml")
local ios_comment_wf = read(".github/workflows/ios-artifact-comment.yml")

-- --- SWCI-01: path detector ---
mustContain(ci, "switch-changes:", "ci.yml")
mustContain(ci, "detect Switch changes", "ci.yml")
mustContain(ci, SWITCH_PATH_REGEX, "ci.yml path regex")
mustContain(ci, 'echo "changed=true"', "ci.yml BASE_SHA fallback")
mustContain(ci, "0000000000000000000000000000000000000000", "ci.yml all-zero BASE_SHA")

-- SWCI-01 extension: NX runtime modules + NX engine suites must be gated
for _, fragment in ipairs({
  "NxAssetOverlay",
  "Platform",
  "GameVersion",
  "CacheFs",
  "assets_version_fallback",
  "nx_generated_guard",
  "nx_yellow_boot",
  "switch_diagnostics",
  "cache_fs_gold_nx_load",
  "tests/engine/platform_nx",
}) do
  mustContain(ci, fragment, "ci.yml path regex NX fragment")
end

-- --- SWCI-02 / SWCI-03: offline selftest job ---
mustContain(ci, "switch-selftest:", "ci.yml")
mustContain(ci, "needs: switch-changes", "ci.yml")
mustContain(ci, "needs.switch-changes.outputs.changed == 'true'", "ci.yml")
mustContain(ci, "scripts/switch/selftest_build_switch.sh", "ci.yml")
mustContain(ci, "scripts/switch/verify_payload.sh --self-test", "ci.yml")
mustContain(ci, "luajit tests/switch_ci_workflows_test.lua", "ci.yml")
mustContain(ci, "luajit tests/switch_transfer_docs_test.lua", "ci.yml")

-- switch-selftest must be ubuntu-latest (fork-safe); pin via job block scan
do
  local start = ci:find("switch-selftest:", 1, true)
  check(start ~= nil, "switch-selftest job present")
  local rest = ci:sub(start)
  local nextJob = rest:find("\n  [%w_-]+:", 2)
  local block = nextJob and rest:sub(1, nextJob - 1) or rest
  mustContain(block, "runs-on: ubuntu-latest", "switch-selftest")
  mustContain(block, "selftest_build_switch.sh", "switch-selftest")
  mustContain(block, "verify_payload.sh --self-test", "switch-selftest")
  mustContain(block, "tests/switch_ci_workflows_test.lua", "switch-selftest")
  mustContain(block, "tests/switch_transfer_docs_test.lua", "switch-selftest")
  mustContain(block, "luajit tests/engine/assets_version_fallback_test.lua", "switch-selftest")
  mustContain(block, "luajit tests/engine/nx_generated_guard_test.lua", "switch-selftest")
  mustContain(block, "luajit tests/engine/nx_yellow_boot_test.lua", "switch-selftest")
  mustContain(block, "luajit tests/engine/cache_fs_gold_nx_load_test.lua", "switch-selftest")
  mustNotContain(block, "continue-on-error:", "switch-selftest")
end

-- --- SWCI-04 / SWCI-05: canonical fused build + artifact ---
mustContain(ci, "switch-build:", "ci.yml")
mustContain(ci, "gen1recomp-switch-nro", "ci.yml")
mustContain(ci, "github.repository == 'bryanthaboi/gen1recomp'", "ci.yml canonical gate")
mustContain(ci, 'runs-on: ["self-hosted", "macOS"]', "ci.yml switch-build runner")
mustContain(ci, "scripts/build_switch.sh --fetch --fused", "ci.yml fused command")
mustContain(ci, "if-no-files-found: error", "ci.yml artifact")
mustContain(ci, "retention-days: 7", "ci.yml artifact retention")
do
  local start = ci:find("switch-build:", 1, true)
  check(start ~= nil, "switch-build job present")
  local rest = ci:sub(start)
  local nextJob = rest:find("\n  [%w_-]+:", 2)
  local block = nextJob and rest:sub(1, nextJob - 1) or rest
  mustContain(block, "needs: [switch-changes, switch-selftest]", "switch-build needs")
  mustContain(block, "needs.switch-selftest.result == 'success'", "switch-build waits for selftest")
  mustContain(block, "always()", "switch-build always() for skipped deps")
  mustContain(block, "needs.switch-changes.outputs.changed == 'true'", "switch-build")
  mustContain(block, "bryanthaboi/gen1recomp", "switch-build canonical")
  mustContain(block, '["self-hosted", "macOS"]', "switch-build runner")
  mustContain(block, "gen1recomp-switch-nro", "switch-build artifact name")
  mustContain(block, "gen1recomp-${{ env.SWITCH_VER }}-switch.nro", "switch-build explicit fused path")
  mustContain(block, "gen1recomp-${{ env.SWITCH_VER }}-switch.nro.sha256", "switch-build sha256 sidecar")
  mustContain(block, "if-no-files-found: error", "switch-build")
  mustContain(block, "retention-days: 7", "switch-build")
  mustNotContain(block, "continue-on-error:", "switch-build")
  -- SWFIX-04: same-repo head only (skip fork→canonical PRs on self-hosted)
  mustContain(block, "pull_request.head.repo.full_name", "switch-build fork-PR skip")
  mustContain(block, "github.event_name != 'pull_request'", "switch-build non-PR allow")
  check(block:find("bryanthaboi/gen1recomp", 1, true) ~= nil
    and block:find("changed == 'true'", 1, true) ~= nil,
    "switch-build requires changed=true AND canonical repository")
end

-- SWFIX-04 / M7: iOS build must NOT gain the Switch fork-PR head.repo guard
do
  local start = ci:find("ios-build:", 1, true)
  check(start ~= nil, "ios-build job present")
  local rest = ci:sub(start)
  local nextJob = rest:find("\n  [%w_-]+:", 2)
  local block = nextJob and rest:sub(1, nextJob - 1) or rest
  mustNotContain(block, "pull_request.head.repo.full_name", "ios-build")
end

-- --- SWCI-06 / SWCI-07 / SWFIX-01: PR artifact comment (no delete-all clobber) ---
mustContain(comment_wf, "workflows: [ci]", "switch-artifact-comment")
mustContain(comment_wf, "gen1recomp-switch-nro", "switch-artifact-comment")
mustContain(comment_wf, "comment-tag: switch-build-result", "switch-artifact-comment")
mustContain(comment_wf, "pull_request", "switch-artifact-comment")
mustContain(comment_wf, "conclusion == 'success'", "switch-artifact-comment")
mustContain(comment_wf, 'exit 0', "switch-artifact-comment no-op")
mustContain(comment_wf, "**Commit**:", "switch-artifact-comment")
mustContain(comment_wf, "**Build Time**:", "switch-artifact-comment")
mustContain(comment_wf, "View workflow run", "switch-artifact-comment")
mustContain(comment_wf, "thollander/actions-comment-pull-request@v3", "switch-artifact-comment")
mustNotContain(comment_wf, "delete-comment", "switch-artifact-comment")
mustNotContain(comment_wf, "izhangzhihao/delete-comment", "switch-artifact-comment")

mustContain(ios_comment_wf, "comment-tag: ios-build-result", "ios-artifact-comment")
mustContain(ios_comment_wf, "thollander/actions-comment-pull-request@v3", "ios-artifact-comment")
mustNotContain(ios_comment_wf, "delete-comment", "ios-artifact-comment")
mustNotContain(ios_comment_wf, "izhangzhihao/delete-comment", "ios-artifact-comment")
-- Distinct tags so both commenters can coexist on the same PR
check(comment_wf:find("comment-tag: switch-build-result", 1, true)
    and ios_comment_wf:find("comment-tag: ios-build-result", 1, true)
    and comment_wf:find("comment-tag: ios-build-result", 1, true) == nil,
  "iOS and Switch comment-tags must be distinct and present")

-- --- SWCI-08 / SWCI-09: docs CI vs release ---
local build_doc = read("docs/switch-build.md")
local readme = read("README.md")

mustContain(build_doc, "Path-gated", "switch-build.md")
mustContain(build_doc, "ubuntu-latest", "switch-build.md")
mustContain(build_doc, "selftest_build_switch.sh", "switch-build.md")
mustContain(build_doc, "main repo", "switch-build.md")
mustContain(build_doc, "gen1recomp-switch-nro", "switch-build.md")
mustContain(build_doc, "switch-build-result", "switch-build.md")
mustContain(build_doc, "hard gate", "switch-build.md")
mustContain(build_doc, "continue-on-error", "switch-build.md")
mustContain(build_doc, "nacptool", "switch-build.md")
mustContain(build_doc, "Docker", "switch-build.md")
mustContain(build_doc, "Fork PRs into the main repo", "switch-build.md")
mustContain(build_doc, "skip Switch fused", "switch-build.md")
mustContain(build_doc, "CI and release", "switch-build.md")
mustNotContain(build_doc, "switch-development", "switch-build.md")
mustNotContain(build_doc, "switch-hardware-evidence", "switch-build.md")

mustContain(readme, "CI vs release", "README.md")
mustContain(readme, "switch-build.md", "README.md")
mustNotContain(readme, "switch-development", "README.md")
mustNotContain(readme, "switch-hardware-evidence", "README.md")

-- --- SWFIX-03: headless suite also runs the content gates ---
local test_sh = read("scripts/test.sh")
mustContain(test_sh, "tests/switch_ci_workflows_test.lua", "scripts/test.sh")
mustContain(test_sh, "T0 switch CI workflow content gate", "scripts/test.sh")
mustContain(test_sh, "tests/switch_transfer_docs_test.lua", "scripts/test.sh")
mustContain(test_sh, "T0 switch transfer docs gate", "scripts/test.sh")
-- NX suites also run in the unified entry point (not only switch-selftest)
mustContain(test_sh, "tests/engine/assets_version_fallback_test.lua", "scripts/test.sh")
mustContain(test_sh, "tests/engine/nx_generated_guard_test.lua", "scripts/test.sh")
mustContain(test_sh, "tests/engine/nx_yellow_boot_test.lua", "scripts/test.sh")
mustContain(test_sh, "tests/engine/cache_fs_gold_nx_load_test.lua", "scripts/test.sh")
mustContain(build_doc, "tests/switch_ci_workflows_test.lua", "switch-build.md path list")
mustContain(build_doc, "tests/switch_transfer_docs_test.lua", "switch-build.md path list")

-- docs parity: switch-build.md must enumerate the NX-gated paths too
for _, path in ipairs({
  "src/core/NxAssetOverlay.lua",
  "src/core/Platform.lua",
  "src/core/GameVersion.lua",
  "src/import/CacheFs.lua",
  "tests/engine/assets_version_fallback_test.lua",
  "tests/engine/nx_generated_guard_test.lua",
  "tests/engine/nx_yellow_boot_test.lua",
  "tests/engine/cache_fs_gold_nx_load_test.lua",
  "tests/engine/switch_diagnostics_test.lua",
  "tests/engine/platform_nx_*",
}) do
  mustContain(build_doc, path, "switch-build.md path list")
end

-- --- SWCI-08: release Switch hard-fail (no continue-on-error on build/stage) ---
do
  local start = release:find("- name: Build Switch", 1, true)
  check(start ~= nil, "release Build Switch step present")
  local rest = release:sub(start)
  local nextStep = rest:find("\n      - name:", 2)
  local block = nextStep and rest:sub(1, nextStep - 1) or rest
  mustContain(block, "scripts/build_switch.sh --fetch --fused", "release Build Switch")
  -- YAML key must be absent (comment prose may discuss soft-fail policy)
  mustNotContain(block, "continue-on-error:", "release Build Switch")
  mustContain(block, "path-gated", "release Build Switch comment")
  mustContain(block, "Hard-fail", "release Build Switch comment")
end

-- Release publishes SD-ready zip only (no bare .nro / .nro.sha256 assets)
do
  local start = release:find("- name: Stage release assets", 1, true)
  check(start ~= nil, "release Stage release assets present")
  local rest = release:sub(start)
  local nextStep = rest:find("\n      - name:", 2)
  local block = nextStep and rest:sub(1, nextStep - 1) or rest
  mustContain(block, "gen1recomp-${v}-switch.zip", "release Stage Switch zip")
  mustContain(block, "pack_sd_zip.sh", "release Stage cites pack_sd_zip")
  mustNotContain(block, "gen1recomp-${v}-switch.nro", "release Stage no bare NRO")
  mustNotContain(block, "switch.nro.sha256", "release Stage no NRO sha256 sidecar")
end

do
  local start = release:find("- name: Publish GitHub Release", 1, true)
  check(start ~= nil, "release Publish GitHub Release present")
  local rest = release:sub(start)
  local nextStep = rest:find("\n      - name:", 2)
  local block = nextStep and rest:sub(1, nextStep - 1) or rest
  mustContain(block, "gen1recomp-${v}-switch.zip", "release Publish Switch zip")
  mustNotContain(block, "gen1recomp-${v}-switch.nro", "release Publish no bare NRO")
  mustNotContain(block, "switch.nro.sha256", "release Publish no NRO sha256 sidecar")
end

T.finish("switch_ci_workflows_test")
