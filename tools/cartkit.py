#!/usr/bin/env python3
"""cartkit: the custom-cart authoring CLI.

    python3 tools/cartkit.py <subcommand> [args]

Subcommands:
    scaffold <id> [--title T] [--author A] [--base red|blue|yellow|gold|silver]
             [--shell "#rrggbb"] [--seal sealed|open] [--summary S]
             [--github owner/repo] [--into DIR] [--force]
    validate <path> [--online] [--no-download] [--strict]
    pin      <path> <spec> [--id ID] [--option k=v]... [--file N]
             [--clear-options]
    pack     <path> [-o out.g1rcart] [--online] [--no-download]
    add-release-workflow <path> [--force]
    selftest

A cart is a manifest, not code: cart.json names a base game and a list of mods
pinned to exact published builds.  <spec> for pin is "owner/repo@1.2.3", a
GameBanana mod URL, or a GameBanana mod id.

Global flags: --repo PATH, --json, --quiet.
Exit codes: 0 success, 1 validation/pack failure, 2 usage error.

validate is offline by default and checks the manifest alone; --online also
resolves every pin against GitHub and GameBanana and compares the published
hash.  A pin that a reachable API says does not exist is a finding; an API
that could not be reached is a note, so a rate limit or a dropped connection
never fails a cart that is fine.  pack runs validate --strict, so a warning
refuses the bundle too.
"""

import argparse
import base64
import contextlib
import hashlib
import io
import json
import os
import re
import shutil
import struct
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib

CARTKIT_VERSION = "1.0.0"
USER_AGENT = ("cartkit/%s (gen1recomp custom carts; "
              "+https://github.com/bryanthaboi/gen1recomp)" % CARTKIT_VERSION)

CART_FILE = "cart.json"
CART_EXT = ".g1rcart"
BUNDLE_FORMAT = "g1rcart"
BUNDLE_VERSION = 1
CART_SCHEMA = 1

BASES = ("red", "blue", "yellow", "gold", "silver", "crystal")
SEALS = ("sealed", "sealed+", "open")
FINISHES = ("sparkle", "holo", "sparkle+holo")
# GameSpeed.LEVELS (src/core/GameSpeed.lua)
SPEED_LEVELS = (1, 2, 3, 4, 10, 20, 30, 50, 75, 100, 200)
SOURCES = ("github", "gamebanana")
MAX_MODS = 64
MAX_OPTIONS = 64
MAX_LABEL_PATH = 128
LABEL_WARN_BYTES = 256 * 1024
LABEL_MAX_BYTES = 1024 * 1024

CART_KEYS = ("schema", "id", "title", "version", "author", "repo", "summary",
             "shell", "finish", "label", "base", "engine", "seal", "speeds",
             "mods", "load_order")
MOD_KEYS = ("id", "source", "repo", "version", "sha256", "mod", "file", "md5",
            "enabled", "options")

ID_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")
SEMVER_RE = re.compile(
    r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?")
SHELL_RE = re.compile(r"#[0-9a-fA-F]{6}")
SHA256_RE = re.compile(r"[0-9a-f]{64}")
MD5_RE = re.compile(r"[0-9a-f]{32}")
REPO_RE = re.compile(r"[A-Za-z0-9][\w.\-]*/[A-Za-z0-9][\w.\-]*")
LABEL_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.\-]*")
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")
LUA_NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

GITHUB_SPEC = re.compile(
    r"^(?:https?://github\.com/)?([\w.\-]+)/([\w.\-]+?)(?:\.git)?@(.+)$")
GITHUB_SLUG = re.compile(
    r"^(?:https?://github\.com/)?([\w.\-]+)/([\w.\-]+?)(?:\.git)?/?$")
GAMEBANANA_SPEC = re.compile(
    r"^(?:gamebanana:|(?:https?://)?(?:www\.)?gamebanana\.com/mods/)?(\d+)/?$")

PLACEHOLDER_REPO = "owner/example-mod"
PLACEHOLDER_SHA = "0" * 64


# ---------------------------------------------------------------- findings

class Finding:
    def __init__(self, rule, severity, message, path=None):
        self.rule = rule
        self.severity = severity
        self.message = message
        self.path = path

    def as_dict(self):
        return {"rule": self.rule, "severity": self.severity,
                "message": self.message, "path": self.path}

    def line(self):
        where = f"{self.path}: " if self.path else ""
        return f"{self.rule} {self.severity.upper():5} {where}{self.message}"


def err(rule, message, path=CART_FILE):
    return Finding(rule, "error", message, path)


def warn(rule, message, path=CART_FILE):
    return Finding(rule, "warn", message, path)


def report(findings, args, summary_ok, summary_fail, notes=None):
    notes = notes or []
    errors = [f for f in findings if f.severity == "error"]
    if getattr(args, "strict", False):
        errors = list(findings)
    if args.json:
        print(json.dumps({"ok": not errors,
                          "findings": [f.as_dict() for f in findings],
                          "notes": notes}))
    else:
        for f in findings:
            print(f.line())
        if not args.quiet:
            for note in notes:
                print(f"cartkit: {note}")
            print(summary_fail if errors else summary_ok)
    return 1 if errors else 0


# ---------------------------------------------------------------- repo/root

def find_repo(start):
    node = os.path.abspath(start)
    while True:
        if os.path.isfile(os.path.join(node, "tools", "rom_manifest.json")):
            return node
        parent = os.path.dirname(node)
        if parent == node:
            return None
        node = parent


def engine_version(repo):
    try:
        src = open(os.path.join(repo, "src", "core", "Version.lua"),
                   encoding="utf-8").read()
    except OSError:
        return "0.0.0-dev"
    match = re.search(r'engine\s*=\s*"([^"]+)"', src)
    return match.group(1) if match else "0.0.0-dev"


def resolve_cart_dir(repo, arg):
    path = os.path.abspath(arg)
    if os.path.isfile(path) and os.path.basename(path) == CART_FILE:
        return os.path.dirname(path)
    if os.path.isdir(path):
        return path
    if repo:
        candidate = os.path.join(repo, "carts", arg)
        if os.path.isdir(candidate):
            return candidate
    return None


def read_cart(cart_dir):
    path = os.path.join(cart_dir, CART_FILE)
    if not os.path.isfile(path):
        return None, err("CK001", f"{CART_FILE} missing; run "
                                  "cartkit scaffold <id> to make one")
    try:
        cart = json.load(open(path, encoding="utf-8"))
    except ValueError as problem:
        return None, err("CK001", f"{CART_FILE} unparseable: {problem}")
    if not isinstance(cart, dict):
        return None, err("CK001", f"{CART_FILE} must be a JSON object")
    return cart, None


def write_cart(cart_dir, cart):
    ordered = {key: cart[key] for key in CART_KEYS if key in cart}
    for key in cart:
        if key not in ordered:
            ordered[key] = cart[key]
    with open(os.path.join(cart_dir, CART_FILE), "w", encoding="utf-8") as fh:
        json.dump(ordered, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


# ---------------------------------------------------------------- schema

def text_problem(value, low, high):
    if not isinstance(value, str):
        return "must be a string"
    if CONTROL_RE.search(value):
        return "must not contain control characters"
    if len(value) < low:
        return f"must be at least {low} character(s)"
    if len(value) > high:
        return f"must be at most {high} characters (got {len(value)})"
    return None


def full_match(pattern, value):
    return isinstance(value, str) and pattern.fullmatch(value) is not None


RANGE_OPS = {"", "=", "==", ">", ">=", "<", "<=", "^"}
RANGE_CORE = re.compile(r"[vV]?\d+(?:\.\d+){0,2}(?:-[0-9A-Za-z.\-]+)?"
                        r"(?:\+[0-9A-Za-z.\-]+)?")


def range_problem(text):
    if not isinstance(text, str) or not text.strip():
        return "must be a non-empty semver range string"
    for alternative in text.split("||"):
        tokens = alternative.split()
        if not tokens:
            return "has an empty alternative around '||'"
        for token in tokens:
            head = re.match(r"^[=<>^]*", token).group(0)
            if head not in RANGE_OPS:
                return f"has an unknown comparator {head!r}"
            if not RANGE_CORE.fullmatch(token[len(head):]):
                return f"has an unparsable version in {token!r}"
    return None


def label_problem(value):
    if not isinstance(value, str) or not value:
        return "must be a non-empty string"
    if len(value) > MAX_LABEL_PATH:
        return f"must be at most {MAX_LABEL_PATH} characters"
    if value.startswith("/") or "\\" in value \
            or re.match(r"^[A-Za-z]:", value):
        return "must be a relative path inside the cart"
    segments = [s for s in value.split("/") if s and s != "."]
    if not segments or any(s == ".." for s in segments):
        return "must not leave the cart directory"
    if not all(LABEL_RE.fullmatch(s) for s in segments):
        return ("must be a plain relative path "
                "(letters, digits, . _ - and /)")
    return None


def option_problems(options, label):
    problems = []
    if not isinstance(options, dict):
        return [f"{label} options must be an object"]
    if len(options) > MAX_OPTIONS:
        problems.append(f"{label} has {len(options)} options (max "
                        f"{MAX_OPTIONS})")
    for key, value in sorted(options.items()):
        if not isinstance(key, str) or CONTROL_RE.search(key):
            problems.append(f"{label} option key {key!r} must be plain text")
            continue
        if not 1 <= len(key) <= 64:
            problems.append(f"{label} option key {key!r} must be 1..64 "
                            "characters")
        if isinstance(value, bool):
            continue
        if isinstance(value, str):
            if CONTROL_RE.search(value):
                problems.append(f"{label} option {key!r} must not contain "
                                "control characters")
            elif len(value) > 256:
                problems.append(f"{label} option {key!r} is {len(value)} "
                                "characters (max 256)")
        elif isinstance(value, (int, float)):
            if isinstance(value, float) and (value != value or
                                             value in (float("inf"),
                                                       float("-inf"))):
                problems.append(f"{label} option {key!r} must be a finite "
                                "number")
        else:
            problems.append(f"{label} option {key!r} must be a string, "
                            "number or boolean")
    return problems


def check_identity(cart, findings):
    schema = cart.get("schema")
    if schema is None:
        findings.append(err("CK002", '"schema" is missing; add "schema": 1'))
    elif isinstance(schema, bool) or not isinstance(schema, int):
        findings.append(err("CK002", '"schema" must be the number 1'))
    elif schema != CART_SCHEMA:
        findings.append(err("CK002", f'"schema" is {schema}; this cartkit '
                                     f"writes and reads schema {CART_SCHEMA}"))

    if not full_match(ID_RE, cart.get("id")):
        findings.append(err("CK002", '"id" must be 1..64 characters of '
                                     "letters, digits, _ or -"))

    for key, low, high in (("title", 1, 48), ("author", 1, 64)):
        problem = text_problem(cart.get(key), low, high)
        if problem:
            findings.append(err("CK002", f'"{key}" {problem}'))

    if not full_match(SEMVER_RE, cart.get("version")):
        findings.append(err("CK002", '"version" must be semver, e.g. 1.0.0'))

    if "repo" in cart and cart["repo"] is not None:
        if not full_match(REPO_RE, cart["repo"]):
            findings.append(err("CK002", '"repo" must be owner/name'))

    if "summary" in cart and cart["summary"] is not None:
        problem = text_problem(cart["summary"], 0, 120)
        if problem:
            findings.append(err("CK002", f'"summary" {problem}'))

    if not full_match(SHELL_RE, cart.get("shell")):
        findings.append(err("CK002", '"shell" must be "#rrggbb", e.g. '
                                     '"#8b1a1a"'))

    if cart.get("base") not in BASES:
        findings.append(err("CK002", '"base" must be one of '
                                     + ", ".join(BASES)))

    if "engine" in cart and cart["engine"] is not None:
        problem = range_problem(cart["engine"])
        if problem:
            findings.append(err("CK002", f'"engine" {problem}; write it like '
                                         '">=1.0.0 <2.0.0"'))

    seal = cart.get("seal", "sealed")
    if seal not in SEALS:
        findings.append(err("CK002", '"seal" must be one of: '
                            + ", ".join(SEALS)))
    finish = cart.get("finish")
    if finish is not None and finish not in FINISHES:
        findings.append(err("CK002", '"finish" must be one of: '
                            + ", ".join(FINISHES)))
    speeds = cart.get("speeds")
    if speeds is not None:
        if not isinstance(speeds, list) or not speeds:
            findings.append(err("CK002",
                                '"speeds" must be a non-empty array'))
        elif any(v not in SPEED_LEVELS for v in speeds):
            findings.append(err("CK002", '"speeds" entries must be game-speed '
                                'levels: '
                                + ", ".join(str(v) for v in SPEED_LEVELS)))

    for key in cart:
        if key not in CART_KEYS:
            findings.append(warn("CK001", f"unknown field {key!r}; cartkit "
                                          "packs only the documented fields"))


def check_label(cart, cart_dir, findings):
    label = cart.get("label")
    if label is None:
        return
    problem = label_problem(label)
    if problem:
        findings.append(err("CK003", f'"label" {problem}'))
        return
    if cart_dir is None:
        return
    path = os.path.join(cart_dir, label)
    if not os.path.isfile(path):
        findings.append(err("CK003", f"label art {label!r} is missing from "
                                     "the cart directory", label))
        return
    if not os.path.realpath(path).startswith(
            os.path.realpath(cart_dir) + os.sep):
        findings.append(err("CK003", f"label art {label!r} resolves outside "
                                     "the cart directory", label))
        return
    if not label.lower().endswith(".png"):
        findings.append(warn("CK003", "label art should be a .png; the game "
                                      "draws nothing else", label))
    size = os.path.getsize(path)
    if size > LABEL_MAX_BYTES:
        findings.append(err("CK003", f"label art is {size} bytes; keep it "
                                     f"under {LABEL_MAX_BYTES} so the bundle "
                                     "stays small", label))
    elif size > LABEL_WARN_BYTES:
        findings.append(warn("CK003", f"label art is {size} bytes; a cart "
                                      "label wants a few KB, not a photo",
                             label))


def check_mods(cart, findings):
    mods = cart.get("mods")
    if not isinstance(mods, list) or not mods:
        findings.append(err("CK004", '"mods" must list 1..64 pinned mods; a '
                                     "cart with no mods is just the base "
                                     "game"))
        return []
    if len(mods) > MAX_MODS:
        findings.append(err("CK004", f'"mods" has {len(mods)} entries (max '
                                     f"{MAX_MODS})"))
    seen = {}
    ids = []
    for index, entry in enumerate(mods):
        label = f"mods[{index + 1}]"
        if not isinstance(entry, dict):
            findings.append(err("CK004", f"{label} must be an object"))
            continue
        mod_id = entry.get("id")
        if not full_match(ID_RE, mod_id):
            findings.append(err("CK004", f"{label} id must be 1..64 "
                                         "characters of letters, digits, _ "
                                         "or -"))
        else:
            label = f"mods[{index + 1}] {mod_id}"
            if mod_id in seen:
                findings.append(err("CK004", f"{label} repeats the id pinned "
                                             f"at mods[{seen[mod_id] + 1}]; "
                                             "one pin per mod"))
            else:
                seen[mod_id] = index
                ids.append(mod_id)
        source = entry.get("source")
        if source == "local":
            findings.append(err("CK004", f"{label} is pinned to one install; "
                                         "a published cart needs a github or "
                                         "gamebanana pin nobody else has to "
                                         "guess at"))
        elif source not in SOURCES:
            findings.append(err("CK004", f"{label} source must be "
                                         + " or ".join(SOURCES)))
        elif source == "github":
            check_github_pin(entry, label, findings)
        else:
            check_gamebanana_pin(entry, label, findings)
        if "enabled" in entry and not isinstance(entry["enabled"], bool):
            findings.append(err("CK004", f"{label} enabled must be true or "
                                         "false; omit it to ship the mod on"))
        if "options" in entry and entry["options"] is not None:
            for problem in option_problems(entry["options"], label):
                findings.append(err("CK004", problem))
        for key in entry:
            if key not in MOD_KEYS:
                findings.append(warn("CK004", f"{label} has unknown field "
                                              f"{key!r}"))
    return ids


def check_github_pin(entry, label, findings):
    if not full_match(REPO_RE, entry.get("repo")):
        findings.append(err("CK004", f"{label} repo must be owner/name"))
    elif str(entry["repo"]).lower() == PLACEHOLDER_REPO:
        findings.append(warn("CK004", f"{label} still points at the scaffold "
                                      "placeholder; pin a real release with "
                                      "cartkit pin <cart> owner/repo@X.Y.Z"))
    if not full_match(SEMVER_RE, entry.get("version")):
        findings.append(err("CK004", f"{label} version must be semver, e.g. "
                                     "1.2.3"))
    sha = entry.get("sha256")
    if not full_match(SHA256_RE, sha):
        findings.append(err("CK004", f"{label} sha256 must be 64 lowercase "
                                     "hex characters; cartkit pin resolves it "
                                     "for you"))
    elif sha == PLACEHOLDER_SHA:
        findings.append(warn("CK004", f"{label} carries the scaffold "
                                      "placeholder hash; resolve it with "
                                      "cartkit pin"))
    for key in ("mod", "file", "md5"):
        if key in entry:
            findings.append(warn("CK004", f"{label} has {key!r}, which "
                                          "belongs to a gamebanana pin"))


def check_gamebanana_pin(entry, label, findings):
    for key in ("mod", "file"):
        value = entry.get(key)
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            findings.append(err("CK004", f"{label} {key} must be a positive "
                                         "integer id"))
    if not full_match(MD5_RE, entry.get("md5")):
        findings.append(err("CK004", f"{label} md5 must be 32 lowercase hex "
                                     "characters; cartkit pin resolves it for "
                                     "you"))
    for key in ("repo", "version", "sha256"):
        if key in entry:
            findings.append(warn("CK004", f"{label} has {key!r}, which "
                                          "belongs to a github pin"))


def check_load_order(cart, ids, findings):
    order = cart.get("load_order")
    if order is None:
        return
    if not isinstance(order, list) or any(not isinstance(x, str)
                                          for x in order):
        findings.append(err("CK005", '"load_order" must be an array of the '
                                     "mod ids"))
        return
    if not ids:
        return
    missing = [x for x in ids if x not in order]
    extra = [x for x in order if x not in ids]
    if len(order) != len(set(order)):
        findings.append(err("CK005", '"load_order" repeats an id; it is a '
                                     "permutation of the mods, not a list of "
                                     "passes"))
    if missing:
        findings.append(err("CK005", '"load_order" leaves out '
                            + ", ".join(missing)
                            + "; name every pinned mod or drop the field"))
    if extra:
        findings.append(err("CK005", '"load_order" names ' + ", ".join(extra)
                            + ", which is not pinned in mods"))


def schema_findings(cart, cart_dir=None):
    findings = []
    check_identity(cart, findings)
    check_label(cart, cart_dir, findings)
    ids = check_mods(cart, findings)
    check_load_order(cart, ids, findings)
    return findings


# ------------------------------------------------------------------- http

class Unreachable(Exception):
    pass


class NotFound(Exception):
    pass


_LAST_REQUEST = [0.0]
MIN_INTERVAL = 0.4
MAX_BACKOFF = 30.0


def github_token():
    for name in ("CARTKIT_GITHUB_TOKEN", "GITHUB_TOKEN", "GH_TOKEN"):
        value = os.environ.get(name, "").strip()
        if value:
            return value
    return None


def _pause():
    wait = MIN_INTERVAL - (time.monotonic() - _LAST_REQUEST[0])
    if wait > 0:
        time.sleep(wait)


def _retry_after(response):
    raw = response.headers.get("Retry-After") if response.headers else None
    try:
        return min(float(raw), MAX_BACKOFF) if raw else None
    except ValueError:
        return None


def open_url(url, accept=None, token=None, timeout=30, attempts=3):
    headers = {"User-Agent": USER_AGENT}
    if accept:
        headers["Accept"] = accept
    if token:
        headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request(url, headers=headers)
    for attempt in range(attempts):
        _pause()
        try:
            response = urllib.request.urlopen(request, timeout=timeout)
            _LAST_REQUEST[0] = time.monotonic()
            return response
        except urllib.error.HTTPError as problem:
            _LAST_REQUEST[0] = time.monotonic()
            if problem.code in (404, 410):
                raise NotFound(url)
            if problem.code == 403 and \
                    problem.headers.get("X-RateLimit-Remaining") == "0":
                raise Unreachable(
                    "GitHub rate limit reached; set GITHUB_TOKEN to a token "
                    "with public read and try again")
            retriable = problem.code in (403, 429) or 500 <= problem.code < 600
            if retriable and attempt + 1 < attempts:
                time.sleep(_retry_after(problem) or min(2 ** attempt * 2,
                                                        MAX_BACKOFF))
                continue
            raise Unreachable(f"{url}: HTTP {problem.code} {problem.reason}")
        except Exception as problem:
            _LAST_REQUEST[0] = time.monotonic()
            if attempt + 1 < attempts:
                time.sleep(min(2 ** attempt, MAX_BACKOFF))
                continue
            raise Unreachable(f"{url}: {problem}")
    raise Unreachable(url)


def get_json(url, accept=None, token=None):
    with open_url(url, accept, token) as response:
        body = response.read()
    try:
        return json.loads(body.decode("utf-8"))
    except ValueError as problem:
        raise Unreachable(f"{url}: response was not JSON ({problem})")


def get_text(url, token=None):
    with open_url(url, None, token) as response:
        return response.read().decode("utf-8", "replace")


def stream_digest(url, algorithm="sha256"):
    digest = hashlib.new(algorithm)
    total = 0
    with open_url(url, timeout=120) as response:
        while True:
            chunk = response.read(262144)
            if not chunk:
                break
            total += len(chunk)
            digest.update(chunk)
    return digest.hexdigest(), total


# --------------------------------------------------------------- resolvers

def github_release(slug, version, token):
    tags = [f"v{version}", version]
    for tag in tags:
        url = (f"https://api.github.com/repos/{slug}/releases/tags/"
               + urllib.parse.quote(tag))
        try:
            return get_json(url, "application/vnd.github+json", token), tag
        except NotFound:
            continue
    raise NotFound(f"{slug} has no release tagged "
                   + " or ".join(tags))


def pick_asset(release, mod_id, version):
    assets = [a for a in release.get("assets", [])
              if isinstance(a, dict) and a.get("name")]
    wanted = f"{mod_id}-{version}.zip"
    for asset in assets:
        if asset["name"] == wanted:
            return asset
    zips = [a for a in assets if a["name"].lower().endswith(".zip")]
    if len(zips) == 1:
        return zips[0]
    if not zips:
        raise NotFound(f"release {release.get('tag_name')} has no .zip asset; "
                       "publish the mod archive on the release")
    names = ", ".join(sorted(a["name"] for a in zips))
    raise NotFound(f"release {release.get('tag_name')} has {len(zips)} .zip "
                   f"assets ({names}); the game picks {wanted}, so name the "
                   "mod archive that way")


def sums_digest(release, asset_name, token):
    for asset in release.get("assets", []):
        if asset.get("name") == "sha256sums.txt":
            body = get_text(asset["browser_download_url"], None)
            for line in body.splitlines():
                parts = line.split()
                if len(parts) == 2 and os.path.basename(
                        parts[1].lstrip("*")) == asset_name:
                    return parts[0].lower()
    return None


def resolve_github(slug, version, mod_id, token, download=True):
    release, tag = github_release(slug, version, token)
    asset = pick_asset(release, mod_id, version)
    digest = sums_digest(release, asset["name"], token)
    how = "sha256sums.txt"
    if digest is None:
        if not download:
            return {"tag": tag, "asset": asset["name"],
                    "size": asset.get("size", 0), "sha256": None,
                    "how": "not published"}
        digest, size = stream_digest(asset["browser_download_url"])
        how = f"downloading {size} bytes"
    return {"tag": tag, "asset": asset["name"], "size": asset.get("size", 0),
            "sha256": digest, "how": how}


def gamebanana_files(mod_id):
    url = f"https://gamebanana.com/apiv11/Mod/{int(mod_id)}/DownloadPage"
    payload = get_json(url)
    if not isinstance(payload, dict):
        raise Unreachable(f"{url}: unexpected response")
    if payload.get("_bIsTrashed") or payload.get("_bIsWithheld"):
        raise NotFound(f"GameBanana mod {mod_id} is trashed or withheld")
    files = payload.get("_aFiles")
    if not isinstance(files, list) or not files:
        raise NotFound(f"GameBanana mod {mod_id} publishes no files")
    return files


def gamebanana_file(files, file_id):
    for entry in files:
        if isinstance(entry, dict) and entry.get("_idRow") == int(file_id):
            return entry
    return None


# ------------------------------------------------------------ online rules

def online_findings(cart, findings, notes, download=True):
    token = github_token()
    if not token:
        notes.append("no GITHUB_TOKEN in the environment; GitHub allows 60 "
                     "anonymous API calls an hour")
    for index, entry in enumerate(cart.get("mods") or []):
        if not isinstance(entry, dict):
            continue
        mod_id = entry.get("id")
        label = f"mods[{index + 1}] {mod_id}"
        if entry.get("source") == "github":
            resolve_github_pin(entry, label, findings, notes, token, download)
        elif entry.get("source") == "gamebanana":
            resolve_gamebanana_pin(entry, label, findings, notes)


def resolve_github_pin(entry, label, findings, notes, token, download):
    slug, version = entry.get("repo"), entry.get("version")
    if not (full_match(REPO_RE, slug) and full_match(SEMVER_RE, version)):
        return
    try:
        found = resolve_github(slug, version, entry.get("id") or "",
                               token, download)
    except NotFound as problem:
        findings.append(err("CK100", f"{label} does not resolve: {problem}"))
        return
    except Unreachable as problem:
        notes.append(f"{label} not resolved: {problem}")
        return
    if found["sha256"] is None:
        notes.append(f"{label} hash not checked: the release publishes no "
                     "sha256sums.txt and --no-download was given")
        return
    if found["sha256"] != entry.get("sha256"):
        findings.append(err("CK101", f"{label} pins sha256 "
                                     f"{entry.get('sha256')} but "
                                     f"{found['asset']} on {slug} "
                                     f"{found['tag']} hashes to "
                                     f"{found['sha256']}; re-pin it"))


def resolve_gamebanana_pin(entry, label, findings, notes):
    mod, file_id = entry.get("mod"), entry.get("file")
    if isinstance(mod, bool) or not isinstance(mod, int) or mod <= 0:
        return
    if isinstance(file_id, bool) or not isinstance(file_id, int) \
            or file_id <= 0:
        return
    try:
        files = gamebanana_files(mod)
    except NotFound as problem:
        findings.append(err("CK110", f"{label} does not resolve: {problem}"))
        return
    except Unreachable as problem:
        notes.append(f"{label} not resolved: {problem}")
        return
    found = gamebanana_file(files, file_id)
    if found is None:
        have = ", ".join(str(f.get("_idRow")) for f in files
                         if isinstance(f, dict))
        findings.append(err("CK110", f"{label} pins file {file_id}, which is "
                                     f"not on GameBanana mod {mod} "
                                     f"(it publishes {have})"))
        return
    published = str(found.get("_sMd5Checksum") or "").lower()
    if published != entry.get("md5"):
        findings.append(err("CK111", f"{label} pins md5 {entry.get('md5')} "
                                     f"but file {file_id} "
                                     f"({found.get('_sFile')}) publishes "
                                     f"{published or 'no checksum'}; "
                                     "re-pin it"))


# -------------------------------------------------------------- lua bundle

def lua_string(text):
    out = ['"']
    for position, ch in enumerate(text):
        code = ord(ch)
        if ch in '"\\\n':
            out.append("\\" + ch)
        elif code < 32 or code == 127:
            following = text[position + 1:position + 2]
            out.append("\\%03d" % code if following.isdigit()
                       else "\\%d" % code)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_number(value):
    if isinstance(value, int):
        return str(value)
    if value != value or value in (float("inf"), float("-inf")):
        raise ValueError(f"cannot serialize {value!r}")
    text = "%.14g" % value
    return text


def lua_value(value, indent=0):
    pad = "  " * indent
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return lua_number(value)
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, (list, tuple)):
        pairs = [(position + 1, item) for position, item in enumerate(value)]
    elif isinstance(value, dict):
        pairs = sorted(value.items(), key=lambda kv: kv[0].encode("utf-8"))
    else:
        raise ValueError(f"cannot serialize {type(value).__name__}")
    if not pairs:
        return "{}"
    lines = []
    for key, item in pairs:
        if isinstance(key, str) and LUA_NAME_RE.fullmatch(key):
            rendered = key
        elif isinstance(key, str):
            rendered = "[" + lua_string(key) + "]"
        else:
            rendered = "[" + lua_number(key) + "]"
        lines.append(pad + "  " + rendered + " = "
                     + lua_value(item, indent + 1))
    return "{\n" + ",\n".join(lines) + ",\n" + pad + "}"


def lua_encode(data):
    return "return " + lua_value(data, 0) + "\n"


def packed_cart(cart):
    out = {}
    for key in CART_KEYS:
        if key in cart and cart[key] is not None:
            out[key] = cart[key]
    out.pop("schema", None)
    out["shell"] = str(cart.get("shell", "")).lower()
    out["seal"] = cart.get("seal", "sealed")
    mods = []
    for entry in cart.get("mods") or []:
        pin = {key: entry[key] for key in MOD_KEYS
               if key in entry and entry[key] is not None}
        if not pin.get("options"):
            pin.pop("options", None)
        mods.append(pin)
    out["mods"] = mods
    out["load_order"] = list(cart.get("load_order")
                             or [entry.get("id") for entry in mods])
    return out


def bundle_table(cart, label_bytes=None, label_name=None):
    root = {"format": BUNDLE_FORMAT, "formatVersion": BUNDLE_VERSION,
            "cart": packed_cart(cart)}
    if label_bytes:
        root["labelArt"] = {
            "name": label_name,
            "encoding": "base64",
            "bytes": len(label_bytes),
            "data": base64.b64encode(label_bytes).decode("ascii"),
        }
    return root


def bundle_bytes(cart, cart_dir=None):
    label_bytes, label_name = None, None
    label = cart.get("label")
    if label and cart_dir:
        path = os.path.join(cart_dir, label)
        if os.path.isfile(path):
            label_bytes = open(path, "rb").read()
            label_name = os.path.basename(label)
    return lua_encode(bundle_table(cart, label_bytes,
                                   label_name)).encode("utf-8")


# ------------------------------------------------------------------ label

def png_bytes(width, height, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for pixel in row:
            raw += bytes(pixel)

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xffffffff))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


def shell_rgb(shell):
    value = shell.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def mix(colour, target, amount):
    return tuple(int(round(c + (t - c) * amount))
                 for c, t in zip(colour, target))


def label_art(shell):
    size = 96
    face = shell_rgb(shell)
    edge = mix(face, (0, 0, 0), 0.55)
    sticker = mix(face, (255, 255, 255), 0.78)
    ink = mix(face, (0, 0, 0), 0.35)
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            inset = min(x, y, size - 1 - x, size - 1 - y)
            if inset < 5:
                row.append(edge)
            elif 12 <= x < size - 12 and 16 <= y < size - 28:
                row.append(sticker if (x + y) % 16 else ink)
            else:
                row.append(face)
        rows.append(row)
    return png_bytes(size, size, rows)


# --------------------------------------------------------------- templates

README_TEMPLATE = """# {{title}}

A custom cart for the LOVE2D Pokemon engine: a pinned mod setup that plays as
its own game on top of `{{base}}`. It ships no code -- every mod named here is
published separately, and the cart pins each one to an exact build.

## Files

- `cart.json` - identity, base game, seal, and one pin per mod
- `{{label}}` - the cart label art the launcher draws
- `.github/workflows/release.yml` - packs and publishes on a `v*` tag

## Loop

Every command below is `tools/cartkit.py` from a gen1recomp checkout, pointed
at this directory.

1. pin a mod:

   ```sh
   python3 tools/cartkit.py pin . owner/repo@1.2.3
   python3 tools/cartkit.py pin . https://gamebanana.com/mods/546899
   ```

2. freeze an option the player inherits:

   ```sh
   python3 tools/cartkit.py pin . owner/repo@1.2.3 --option difficulty=hard
   ```

3. check it, hashes and all:

   ```sh
   python3 tools/cartkit.py validate . --online
   ```

4. build the bundle players load:

   ```sh
   python3 tools/cartkit.py pack .
   ```

`seal` is `{{seal}}`. A sealed cart loads exactly the mods listed below and
nothing else; an open cart lets the player add more on top.

## Releasing

Bump `version` in `cart.json`, tag it `v<version>`, and push the tag. The
workflow validates, packs, and attaches `{{id}}-<version>.g1rcart` to the
release.
"""

CHANGELOG_TEMPLATE = """# Changelog

All notable changes to this cart are recorded here, newest first.

## [0.1.0] - unreleased

### Added

- First cut of {{title}}.
"""


def cmd_scaffold(args, repo):
    if not ID_RE.fullmatch(args.id):
        print(f"cartkit: bad id {args.id!r} (letters, digits, _ or -, "
              "1..64 characters)")
        return 2
    if args.shell and not SHELL_RE.fullmatch(args.shell):
        print(f"cartkit: bad shell {args.shell!r} (expected #rrggbb)")
        return 2
    github = ""
    if args.github:
        match = GITHUB_SLUG.fullmatch(args.github.strip())
        if not match:
            print(f"cartkit: bad --github {args.github!r} "
                  "(expected owner/name or a github.com URL)")
            return 2
        github = f"{match.group(1)}/{match.group(2)}"

    dest_root = args.into or args.dest or (os.path.join(repo, "carts")
                                           if repo else os.getcwd())
    dest = os.path.join(dest_root, args.id)
    if os.path.exists(dest) and not args.force:
        print(f"cartkit: {dest} exists (use --force to overwrite)")
        return 2

    title = args.title or args.id.replace("_", " ").replace("-", " ").title()
    if text_problem(title, 1, 48):
        print(f"cartkit: bad title {title!r} (1..48 characters)")
        return 2
    shell = (args.shell or "#8b1a1a").lower()
    engine = engine_version(repo) if repo else "0.0.0"
    engine_range = ">=%s <%d.0.0" % (engine, int(engine.split(".")[0]) + 1)

    cart = {
        "schema": CART_SCHEMA,
        "id": args.id,
        "title": title,
        "version": "0.1.0",
        "author": args.author or "TODO your handle",
        "summary": args.summary or "",
        "shell": shell,
        "label": "label.png",
        "base": args.base,
        "engine": engine_range,
        "seal": args.seal,
        "mods": [{
            "id": "example-mod",
            "source": "github",
            "repo": PLACEHOLDER_REPO,
            "version": "0.1.0",
            "sha256": PLACEHOLDER_SHA,
        }],
    }
    if github:
        cart["repo"] = github
    if not cart["summary"]:
        del cart["summary"]

    os.makedirs(dest, exist_ok=True)
    write_cart(dest, cart)
    with open(os.path.join(dest, "label.png"), "wb") as fh:
        fh.write(label_art(shell))
    subst = {"{{id}}": args.id, "{{title}}": title, "{{base}}": args.base,
             "{{seal}}": args.seal, "{{label}}": "label.png"}
    for name, template in (("README.md", README_TEMPLATE),
                           ("CHANGELOG.md", CHANGELOG_TEMPLATE)):
        body = template
        for key, value in subst.items():
            body = body.replace(key, value)
        with open(os.path.join(dest, name), "w", encoding="utf-8") as fh:
            fh.write(body)
    install_workflow(repo, dest, args.id, force=True)

    if not args.quiet:
        print(f"created {dest} ({args.base} base, {args.seal})")
        print("next: python3 tools/cartkit.py pin "
              f"{dest} owner/repo@1.2.3   (replaces the placeholder pin)")
        print(f"then: python3 tools/cartkit.py validate {dest} --online")
    return 0


# ---------------------------------------------------------------- workflow

def install_workflow(repo, cart_dir, cart_id, force=False):
    template = os.path.join(repo or "", "tools", "cart_release_workflow.yml")
    if not os.path.isfile(template):
        return f"missing template {template}"
    dest_dir = os.path.join(cart_dir, ".github", "workflows")
    dest = os.path.join(dest_dir, "release.yml")
    if os.path.exists(dest) and not force:
        return f"{dest} exists (use --force to overwrite)"
    body = open(template, encoding="utf-8").read().replace("{{CART_ID}}",
                                                           cart_id)
    os.makedirs(dest_dir, exist_ok=True)
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write(body)
    return None


def cmd_add_release_workflow(args, repo):
    cart_dir = resolve_cart_dir(repo, args.cart)
    if not cart_dir:
        print(f"cartkit: no cart at {args.cart!r}")
        return 2
    cart, problem = read_cart(cart_dir)
    if problem:
        print(problem.line())
        return 1
    cart_id = cart.get("id") or os.path.basename(cart_dir)
    trouble = install_workflow(repo, cart_dir, cart_id, args.force)
    if trouble:
        print(f"cartkit: {trouble}")
        return 2
    if not args.quiet:
        dest = os.path.join(cart_dir, ".github", "workflows", "release.yml")
        print(f"wrote {dest}")
        print("push the cart as its own GitHub repo and tag v<version> to "
              f"publish {cart_id}-<version>{CART_EXT}")
    return 0


# ---------------------------------------------------------------- validate

def cmd_validate(args, repo):
    cart_dir = resolve_cart_dir(repo, args.cart)
    if not cart_dir:
        print(f"cartkit: no cart at {args.cart!r} (expected a directory "
              f"holding {CART_FILE})")
        return 2
    cart, problem = read_cart(cart_dir)
    findings, notes = [], []
    if problem:
        findings.append(problem)
        name = os.path.basename(cart_dir)
    else:
        findings.extend(schema_findings(cart, cart_dir))
        name = cart.get("id") or os.path.basename(cart_dir)
        if args.online:
            online_findings(cart, findings, notes, not args.no_download)
        else:
            notes.append("pins not resolved; rerun with --online to check "
                         "every release, file id and hash")
    return report(findings, args, f"ok {name} valid", f"FAIL {name} invalid",
                  notes)


# -------------------------------------------------------------------- pack

def cmd_pack(args, repo):
    cart_dir = resolve_cart_dir(repo, args.cart)
    if not cart_dir:
        print(f"cartkit: no cart at {args.cart!r}")
        return 2
    cart, problem = read_cart(cart_dir)
    if problem:
        print(problem.line())
        return 1
    findings = schema_findings(cart, cart_dir)
    notes = []
    if args.online:
        online_findings(cart, findings, notes, not args.no_download)
    for finding in findings:
        print(finding.line())
    if not args.quiet:
        for note in notes:
            print(f"cartkit: {note}")
    if findings:
        print("cartkit: pack refused (pack runs validate --strict, so the "
              "warnings above are fatal too)")
        return 1

    out = args.output or f"{cart['id']}-{cart['version']}{CART_EXT}"
    body = bundle_bytes(cart, cart_dir)
    with open(out, "wb") as fh:
        fh.write(body)
    if not args.quiet:
        mods = len(cart.get("mods") or [])
        label = " + label art" if cart.get("label") else ""
        plural = "" if mods == 1 else "s"
        print(f"wrote {out} ({len(body)} bytes, {mods} pinned "
              f"mod{plural}{label})")
    return 0


# --------------------------------------------------------------------- pin

def parse_spec(spec):
    match = GITHUB_SPEC.fullmatch(spec.strip())
    if match:
        return ("github", f"{match.group(1)}/{match.group(2)}",
                match.group(3).lstrip("vV"))
    match = GAMEBANANA_SPEC.fullmatch(spec.strip())
    if match:
        return ("gamebanana", int(match.group(1)), None)
    return (None, None, None)


def parse_option(text):
    key, sep, raw = text.partition("=")
    if not sep or not key:
        raise ValueError(f"--option wants key=value (got {text!r})")
    lowered = raw.strip().lower()
    if lowered in ("true", "false"):
        return key, lowered == "true"
    try:
        return key, int(raw)
    except ValueError:
        pass
    try:
        return key, float(raw)
    except ValueError:
        pass
    return key, raw


def is_placeholder(entry):
    return (isinstance(entry, dict)
            and str(entry.get("repo", "")).lower() == PLACEHOLDER_REPO
            and entry.get("sha256") == PLACEHOLDER_SHA)


def derive_id(text):
    cleaned = re.sub(r"[^A-Za-z0-9_-]+", "-", text.strip()).strip("-")
    return (cleaned or "mod")[:64].lower()


def cmd_pin(args, repo):
    cart_dir = resolve_cart_dir(repo, args.cart)
    if not cart_dir:
        print(f"cartkit: no cart at {args.cart!r}")
        return 2
    cart, problem = read_cart(cart_dir)
    if problem:
        print(problem.line())
        return 1
    source, target, version = parse_spec(args.spec)
    if not source:
        print(f"cartkit: cannot read {args.spec!r}; write owner/repo@1.2.3, a "
              "gamebanana mod url, or a gamebanana mod id")
        return 2
    if source == "github" and not SEMVER_RE.fullmatch(version):
        print(f"cartkit: {version!r} is not semver; pin an exact release like "
              "owner/repo@1.2.3")
        return 2
    options = {}
    try:
        for text in args.option or []:
            key, value = parse_option(text)
            options[key] = value
    except ValueError as problem:
        print(f"cartkit: {problem}")
        return 2

    try:
        if source == "github":
            entry, note = pin_github(target, version, args, options)
        else:
            entry, note = pin_gamebanana(target, args, options)
    except NotFound as problem:
        print(f"cartkit: {problem}")
        return 1
    except Unreachable as problem:
        print(f"cartkit: {problem}")
        return 1
    if entry is None:
        return 2

    mods = cart.setdefault("mods", [])
    replaced = False
    for index, existing in enumerate(mods):
        if isinstance(existing, dict) and existing.get("id") == entry["id"]:
            keep = existing.get("options") or {}
            if args.clear_options:
                keep = {}
            keep.update(entry.get("options") or {})
            if keep:
                entry["options"] = keep
            mods[index] = entry
            replaced = True
            break
    dropped = []
    if not replaced:
        for existing in list(mods):
            if is_placeholder(existing):
                mods.remove(existing)
                dropped.append(existing.get("id"))
        mods.append(entry)
        order = cart.get("load_order")
        if isinstance(order, list):
            cart["load_order"] = [x for x in order if x not in dropped]
            cart["load_order"].append(entry["id"])
    write_cart(cart_dir, cart)

    if not args.quiet:
        verb = "updated" if replaced else "added"
        print(f"{verb} pin {entry['id']} ({note})")
        for name in dropped:
            print(f"dropped the scaffold placeholder pin {name}")
        print(f"wrote {os.path.join(cart_dir, CART_FILE)}")
    return 0


def pin_github(slug, version, args, options):
    mod_id = args.id or derive_id(slug.split("/")[1])
    found = resolve_github(slug, version, mod_id, github_token(), True)
    if found["sha256"] is None:
        raise NotFound(f"{slug} {found['tag']} publishes no hash for "
                       f"{found['asset']}")
    entry = {"id": mod_id, "source": "github", "repo": slug,
             "version": version, "sha256": found["sha256"]}
    if options:
        entry["options"] = options
    return entry, (f"{slug} {found['tag']} -> {found['asset']}, sha256 from "
                   f"{found['how']}")


def pin_gamebanana(mod_id, args, options):
    files = gamebanana_files(mod_id)
    chosen = None
    if args.file:
        chosen = gamebanana_file(files, args.file)
        if chosen is None:
            have = ", ".join(f"{f.get('_idRow')} ({f.get('_sFile')})"
                             for f in files if isinstance(f, dict))
            raise NotFound(f"GameBanana mod {mod_id} has no file "
                           f"{args.file}; it publishes {have}")
    elif len(files) == 1:
        chosen = files[0]
    else:
        have = "\n".join(f"  --file {f.get('_idRow')}  {f.get('_sFile')}"
                         for f in files if isinstance(f, dict))
        print(f"cartkit: GameBanana mod {mod_id} publishes {len(files)} "
              f"files; pick one:\n{have}")
        return None, None
    md5 = str(chosen.get("_sMd5Checksum") or "").lower()
    if not MD5_RE.fullmatch(md5):
        raise NotFound(f"GameBanana file {chosen.get('_idRow')} publishes no "
                       "md5; a cart cannot pin it")
    name = args.id or derive_id(os.path.splitext(
        str(chosen.get("_sFile") or ""))[0]) or f"gb{mod_id}"
    entry = {"id": name, "source": "gamebanana", "mod": int(mod_id),
             "file": int(chosen["_idRow"]), "md5": md5}
    if options:
        entry["options"] = options
    return entry, (f"gamebanana {mod_id} -> file {chosen['_idRow']} "
                   f"({chosen.get('_sFile')}), md5 from the v11 API")


# ---------------------------------------------------------------- selftest

def good_cart():
    return {
        "schema": 1,
        "id": "kanto-hard",
        "title": "Kanto Hard Mode",
        "version": "1.0.0",
        "author": "someone",
        "repo": "someone/kanto-hard",
        "summary": "Every trainer bites back.",
        "shell": "#8b1a1a",
        "label": "label.png",
        "base": "red",
        "engine": ">=1.0.0 <2.0.0",
        "seal": "sealed",
        "mods": [
            {"id": "harder-trainers", "source": "github",
             "repo": "someone/harder-trainers", "version": "2.1.0",
             "sha256": "a" * 64,
             "options": {"difficulty": "brutal", "levelCap": 100,
                         "nuzlocke": True}},
            {"id": "new-music", "source": "gamebanana", "mod": 546899,
             "file": 1294214, "md5": "b" * 32},
        ],
        "load_order": ["new-music", "harder-trainers"],
    }


def rules(findings):
    return sorted({f.rule for f in findings if f.severity == "error"})


def t_good():
    found = schema_findings(good_cart())
    assert not found, rules(found)


def t_identity():
    for key, value in (("id", "no spaces here"), ("id", "x" * 65),
                       ("title", ""), ("title", "t" * 49),
                       ("version", "1.0"), ("version", "v1.0.0"),
                       ("author", ""), ("shell", "8b1a1a"),
                       ("shell", "#8b1a1"), ("base", "nonesuch"),
                       ("seal", "welded"), ("schema", 2),
                       ("summary", "s" * 121), ("repo", "someone"),
                       ("engine", ">=1.0.0 <<2.0.0")):
        cart = good_cart()
        cart[key] = value
        assert "CK002" in rules(schema_findings(cart)), (key, value)


def t_optional_fields():
    for key in ("repo", "summary", "engine", "label", "load_order", "seal"):
        cart = good_cart()
        del cart[key]
        assert not schema_findings(cart), key


def t_unknown_field():
    cart = good_cart()
    cart["colour"] = "red"
    assert any(f.rule == "CK001" and f.severity == "warn"
               for f in schema_findings(cart))


def t_label():
    for value in ("/etc/passwd", "../out.png", "a/../../b.png", "x" * 129,
                  "C:\\art.png"):
        cart = good_cart()
        cart["label"] = value
        assert "CK003" in rules(schema_findings(cart)), value


def t_mods():
    cart = good_cart()
    cart["mods"] = []
    assert "CK004" in rules(schema_findings(cart))
    cart = good_cart()
    cart["mods"] = [dict(cart["mods"][0]) for _ in range(65)]
    assert "CK004" in rules(schema_findings(cart))
    cart = good_cart()
    cart["mods"][1] = dict(cart["mods"][0])
    cart["load_order"] = ["harder-trainers", "harder-trainers"]
    assert "CK004" in rules(schema_findings(cart))


def t_pins():
    cases = [
        {"source": "torrent"},
        {"repo": "nope"},
        {"version": "1.0"},
        {"sha256": "A" * 64},
        {"sha256": "a" * 63},
    ]
    for patch in cases:
        cart = good_cart()
        cart["mods"][0].update(patch)
        assert "CK004" in rules(schema_findings(cart)), patch
    for patch in [{"mod": 0}, {"mod": "546899"}, {"file": -1},
                  {"md5": "B" * 32}, {"md5": "b" * 31}]:
        cart = good_cart()
        cart["mods"][1].update(patch)
        assert "CK004" in rules(schema_findings(cart)), patch


def t_placeholder_warns():
    cart = good_cart()
    cart["mods"][0]["repo"] = PLACEHOLDER_REPO
    cart["mods"][0]["sha256"] = PLACEHOLDER_SHA
    found = schema_findings(cart)
    assert not rules(found)
    assert sum(1 for f in found if f.severity == "warn") == 2


def t_options():
    for value in ({"a": {"nested": 1}}, {"a": None}, {"a": ["list"]},
                  {"k" * 65: 1}, {"a": "x" * 257},
                  dict((str(n), n) for n in range(65))):
        cart = good_cart()
        cart["mods"][0]["options"] = value
        assert "CK004" in rules(schema_findings(cart)), value


def t_load_order():
    for value in (["harder-trainers"], ["harder-trainers", "ghost"],
                  ["harder-trainers", "harder-trainers"], "harder-trainers",
                  [1, 2]):
        cart = good_cart()
        cart["load_order"] = value
        assert "CK005" in rules(schema_findings(cart)), value


def t_lua_strings():
    assert lua_string('a"b') == '"a\\"b"'
    assert lua_string("a\\b") == '"a\\\\b"'
    assert lua_string("a\nb") == '"a\\\nb"'
    assert lua_string("a\tb") == '"a\\9b"'
    assert lua_string("a\t1") == '"a\\0091"'
    assert lua_string("a\rb") == '"a\\13b"'
    assert lua_string("Pokémon") == '"Pokémon"'


def t_lua_numbers():
    assert lua_value(3) == "3"
    assert lua_value(-2) == "-2"
    assert lua_value(0.5) == "0.5"
    assert lua_value(True) == "true"
    assert lua_value([]) == "{}"
    assert lua_value({}) == "{}"


def t_bundle_shape():
    body = lua_encode(bundle_table(good_cart()))
    assert body.startswith("return {\n")
    assert body.endswith("}\n")
    assert '  format = "g1rcart",' in body
    assert "  formatVersion = 1,\n" in body
    assert body.index("cart =") < body.index("format =") < \
        body.index("formatVersion =")
    assert '[1] = {' in body


def t_bundle_defaults():
    cart = good_cart()
    del cart["seal"]
    del cart["load_order"]
    packed = packed_cart(cart)
    assert packed["seal"] == "sealed"
    assert packed["load_order"] == ["harder-trainers", "new-music"]


def t_bundle_deterministic():
    cart = good_cart()
    shuffled = {key: cart[key] for key in reversed(list(cart))}
    assert lua_encode(bundle_table(cart)) == lua_encode(bundle_table(shuffled))


def t_bundle_label():
    art = label_art("#8b1a1a")
    table = bundle_table(good_cart(), art, "label.png")
    assert table["labelArt"]["bytes"] == len(art)
    assert base64.b64decode(table["labelArt"]["data"]) == art


def t_specs():
    assert parse_spec("owner/repo@1.2.3") == ("github", "owner/repo", "1.2.3")
    assert parse_spec("https://github.com/owner/repo@1.2.3") == \
        ("github", "owner/repo", "1.2.3")
    assert parse_spec("owner/repo.git@v1.2.3") == \
        ("github", "owner/repo", "1.2.3")
    assert parse_spec("https://gamebanana.com/mods/546899") == \
        ("gamebanana", 546899, None)
    assert parse_spec("gamebanana:546899") == ("gamebanana", 546899, None)
    assert parse_spec("546899") == ("gamebanana", 546899, None)
    assert parse_spec("not a spec")[0] is None


def t_options_parse():
    assert parse_option("a=true") == ("a", True)
    assert parse_option("a=3") == ("a", 3)
    assert parse_option("a=1.5") == ("a", 1.5)
    assert parse_option("a=hard") == ("a", "hard")
    try:
        parse_option("nope")
    except ValueError:
        return
    raise AssertionError("--option without = must be rejected")


def t_ranges():
    for text in (">=1.0.0 <2.0.0", "^1.2", "1.2.3", ">1 || <0.9", "<=2"):
        assert range_problem(text) is None, text
    for text in ("", ">=x", ">>1.0.0", "1.0.0 || "):
        assert range_problem(text) is not None, text


def t_png():
    art = label_art("#123456")
    assert art.startswith(b"\x89PNG\r\n\x1a\n")
    assert art[12:16] == b"IHDR" and art.endswith(b"IEND\xae\x42\x60\x82")
    assert label_art("#123456") == art


class SelftestSkip(Exception):
    pass


def t_roundtrip():
    root = tempfile.mkdtemp(prefix="cartkit-selftest-")
    repo = find_repo(os.getcwd()) or find_repo(
        os.path.dirname(os.path.abspath(__file__)))
    if not repo:
        raise SelftestSkip("scaffold needs an engine checkout; none found "
                           "from the cwd or the script")
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            _roundtrip(root, repo)
    finally:
        shutil.rmtree(root, ignore_errors=True)


def _roundtrip(root, repo):
        assert main(["scaffold", "demo_cart", "--into", root,
                     "--quiet"]) == 0, "scaffold failed"
        cart_dir = os.path.join(root, "demo_cart")
        assert os.path.isfile(os.path.join(cart_dir, CART_FILE))
        assert os.path.isfile(os.path.join(cart_dir, "label.png"))
        assert os.path.isfile(os.path.join(cart_dir, "README.md"))
        assert os.path.isfile(os.path.join(cart_dir, "CHANGELOG.md"))
        assert os.path.isfile(os.path.join(cart_dir, ".github", "workflows",
                                           "release.yml")) or not repo
        assert main(["validate", cart_dir, "--quiet"]) == 0, "validate failed"
        assert main(["validate", cart_dir, "--quiet", "--strict"]) == 1, \
            "the placeholder pin must fail --strict"
        cart, problem = read_cart(cart_dir)
        assert problem is None
        cart["mods"][0] = {"id": "harder-trainers", "source": "github",
                           "repo": "someone/harder-trainers",
                           "version": "2.1.0", "sha256": "c" * 64}
        write_cart(cart_dir, cart)
        assert main(["pack", cart_dir, "-o",
                     os.path.join(root, "out" + CART_EXT), "--quiet"]) == 0
        first = open(os.path.join(root, "out" + CART_EXT), "rb").read()
        assert main(["pack", cart_dir, "-o",
                     os.path.join(root, "again" + CART_EXT), "--quiet"]) == 0
        again = open(os.path.join(root, "again" + CART_EXT), "rb").read()
        assert first == again, "pack is not byte-identical twice"
        assert first.startswith(b"return {\n")
        assert b'id = "demo_cart"' in first
        assert b'labelArt' in first


CHECKS = [
    ("schema accepts a full cart", t_good),
    ("identity fields are checked", t_identity),
    ("optional fields stay optional", t_optional_fields),
    ("unknown top-level fields warn", t_unknown_field),
    ("label paths cannot escape", t_label),
    ("mods list bounds", t_mods),
    ("pin fields per source", t_pins),
    ("scaffold placeholders warn", t_placeholder_warns),
    ("frozen options are scalars", t_options),
    ("load_order is a permutation", t_load_order),
    ("lua string escapes", t_lua_strings),
    ("lua scalars and empty tables", t_lua_numbers),
    ("bundle shape and key order", t_bundle_shape),
    ("bundle materializes defaults", t_bundle_defaults),
    ("bundle is order-independent", t_bundle_deterministic),
    ("bundle carries the label art", t_bundle_label),
    ("pin specs", t_specs),
    ("option parsing", t_options_parse),
    ("engine ranges", t_ranges),
    ("label png is deterministic", t_png),
    ("scaffold validate pack round trip", t_roundtrip),
]


def cmd_selftest(args, repo):
    failures = []
    skipped = []
    for name, check in CHECKS:
        try:
            check()
        except SelftestSkip as why:
            skipped.append((name, why))
            print(f"skip {name}: {why}")
        except Exception as problem:
            failures.append((name, problem))
            print(f"FAIL {name}: {problem!r}")
        else:
            if not args.quiet:
                print(f"ok   {name}")
    if failures:
        print(f"FAIL {len(failures)} of {len(CHECKS)} checks")
        return 1
    ran = len(CHECKS) - len(skipped)
    tail = f" ({len(skipped)} skipped)" if skipped else ""
    if not args.quiet:
        print(f"ok {ran} checks{tail}")
    return 0


# -------------------------------------------------------------------- main

def main(argv):
    shared = argparse.ArgumentParser(add_help=False)
    shared.add_argument("--repo", default=argparse.SUPPRESS,
                        help="repo root override")
    shared.add_argument("--json", action="store_true",
                        default=argparse.SUPPRESS)
    shared.add_argument("--quiet", action="store_true",
                        default=argparse.SUPPRESS)

    parser = argparse.ArgumentParser(prog="cartkit", parents=[shared],
                                     description="author, check and pack "
                                                 "custom carts")
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("scaffold", parents=[shared],
                       help="write a new cart repo")
    p.add_argument("id")
    p.add_argument("--title", help="shown on the cart, 1..48 characters")
    p.add_argument("--author")
    p.add_argument("--summary", help="one line, <=120 characters")
    p.add_argument("--base", default="red", choices=list(BASES))
    p.add_argument("--shell", help="cart shell colour as #rrggbb")
    p.add_argument("--seal", default="sealed", choices=list(SEALS),
                   help="sealed loads only the pinned mods; open lets the "
                        "player add more")
    p.add_argument("--github", help="owner/repo this cart is published from")
    p.add_argument("--into", help="parent directory for the new cart")
    p.add_argument("--dest", help=argparse.SUPPRESS)
    p.add_argument("--force", action="store_true")

    p = sub.add_parser("validate", parents=[shared],
                       help="check cart.json, offline unless --online")
    p.add_argument("cart")
    p.add_argument("--online", action="store_true",
                   help="resolve every pin against GitHub and GameBanana")
    p.add_argument("--no-download", action="store_true",
                   help="never fetch a release asset just to hash it")
    p.add_argument("--strict", action="store_true")

    p = sub.add_parser("pin", parents=[shared],
                       help="add or update one pin, resolving its hash")
    p.add_argument("cart")
    p.add_argument("spec", help="owner/repo@1.2.3, a gamebanana mod url, or "
                                "a gamebanana mod id")
    p.add_argument("--id", help="mod id in the cart (default: derived)")
    p.add_argument("--file", type=int,
                   help="gamebanana file id when the mod publishes several")
    p.add_argument("--option", action="append", metavar="KEY=VALUE",
                   help="freeze an option value; true/false and numbers are "
                        "stored as such")
    p.add_argument("--clear-options", action="store_true",
                   help="drop option values already frozen on this pin")

    p = sub.add_parser("pack", parents=[shared],
                       help="write <id>-<version>" + CART_EXT)
    p.add_argument("cart")
    p.add_argument("-o", "--output")
    p.add_argument("--online", action="store_true")
    p.add_argument("--no-download", action="store_true")

    p = sub.add_parser("add-release-workflow", parents=[shared],
                       help="copy the GitHub Actions release workflow in")
    p.add_argument("cart")
    p.add_argument("--force", action="store_true")

    sub.add_parser("selftest", parents=[shared],
                   help="run cartkit's own checks")

    args = parser.parse_args(argv)
    for dest, fallback in (("repo", None), ("json", False), ("quiet", False)):
        if not hasattr(args, dest):
            setattr(args, dest, fallback)
    if not args.command:
        parser.print_help()
        return 2

    repo = args.repo or find_repo(os.getcwd()) or find_repo(
        os.path.dirname(os.path.abspath(__file__)))
    if repo:
        repo = os.path.abspath(repo)
    elif args.command in ("scaffold", "add-release-workflow"):
        print("cartkit: cannot find the repo root "
              "(looked for tools/rom_manifest.json); pass --repo PATH")
        return 2

    handler = {
        "scaffold": cmd_scaffold,
        "validate": cmd_validate,
        "pin": cmd_pin,
        "pack": cmd_pack,
        "add-release-workflow": cmd_add_release_workflow,
        "selftest": cmd_selftest,
    }[args.command]
    return handler(args, repo)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
