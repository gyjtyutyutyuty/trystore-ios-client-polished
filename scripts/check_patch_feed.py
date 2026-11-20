#!/usr/bin/env python3
"""Walk the exact chain the app uses and print where patch delivery breaks.

The app asks the licence service, then the feed for a bundle key, a manifest and
a package. Every one of those steps can fail on its own, and the app only sees
"unauthorized". This runs the same requests with the same headers, in order, and
names the step that fails.

Usage:
    python3 scripts/check_patch_feed.py --key "<licence key>" --device "<uuid>"

The key is never printed. It is read from --key or TRYSTORE_LICENSE_KEY.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

FEED = "https://trystore-patch-feed.burgoajustin.workers.dev"
LICENCE = "https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate"
PROJECT = "trystore"

EXPECTED_CATALOG = {
    "HEAD.TRYSTORE",
    "NECK.TRYSTORE",
    "HSPESSCOSO.TRYSTORE",
    "HS SLA PECHO.TRYSTORE",
    "EXCLUSIVO AZUL.TRYSTORE",
    "TryStore.TRYSTORE",
    "HOLOGRAMAEXCLUSIVO(4).TRYSTORE",
    "HOLOGRAMAEXCLUSIVO(5).TRYSTORE",
    "Cuello y Drag.TRYSTORE",
    "Pecho3105.TRYSTORE",
    "CUELLO3105.TRYSTORE",
}

FIXES = {
    "license_service_unreachable": "the RESELLER binding exists but the licence service did not "
                                   "answer the feed's own check",
    "license_service_unbound": "the deployed Worker has no RESELLER service binding; deploy with "
                               "the committed cloudflare/wrangler.toml",
    "license_not_found": "the key is not a global_keys row for project trystore and the legacy "
                         "forward rejected it",
    "license_invalid": "the licence service does not know this key",
    "license_expired": "the key has expired",
    "license_frozen": "the key is frozen or its reseller subscription lapsed",
    "license_revoked": "the key was revoked",
    "license_wrong_project": "the key belongs to a different project",
}


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def request(url: str, headers: dict[str, str], body: dict | None = None):
    headers = {"user-agent": "TryStoreFeedCheck/1.0", **headers}
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except Exception as error:  # noqa: BLE001 - transport failures are the point
        fail(f"{url} did not answer: {error}")


def explain(payload: bytes) -> str:
    try:
        parsed = json.loads(payload)
    except Exception:
        # Something that is not our JSON, usually an edge error page.
        return payload[:200].decode("utf-8", "replace").strip()
    reason = str(parsed.get("outcome") or parsed.get("error") or "")
    if not reason:
        return json.dumps(parsed)
    fix = FIXES.get(reason)
    return reason + (f"  → {fix}" if fix else "")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key", default=os.environ.get("TRYSTORE_LICENSE_KEY", ""))
    parser.add_argument("--device", required=True, help="the per-install UUID the app sends")
    parser.add_argument("--app-version", default="1.1.1")
    parser.add_argument("--feed", default=FEED)
    parser.add_argument("--licence", default=LICENCE)
    args = parser.parse_args()

    if not args.key.strip():
        fail("provide --key or TRYSTORE_LICENSE_KEY")
    key = args.key.strip().upper()
    masked = f"••••-{key[-4:]}"
    print(f"key {masked}  device {args.device}  app {args.app_version}\n")

    print("1. licence service (what the app calls at launch)")
    status, payload = request(
        args.licence,
        {"content-type": "application/json", "cache-control": "no-store"},
        {
            "key": key,
            "deviceId": args.device,
            "appVersion": args.app_version,
            "projectId": PROJECT,
        },
    )
    print(f"   HTTP {status}  {explain(payload)}")
    try:
        body = json.loads(payload)
    except Exception:
        body = {}
    if not (status == 200 and body.get("valid") is True
            and str(body.get("outcome", "")).lower() == "active"):
        fail("the licence gate rejects this key, so no build will sync. Fix that first.")

    headers = {
        "authorization": f"Bearer {key}",
        "x-trystore-device-id": args.device,
        "cache-control": "no-store",
    }

    print("2. bundle key (what unlocks every package)")
    status, payload = request(f"{args.feed}/api/patches/{PROJECT}/bundle-key", headers)
    if status == 200:
        try:
            bundle_key = base64.b64decode(json.loads(payload)["key"], validate=True)
        except Exception:
            fail("bundle-key answered 200 but not with a base64 32-byte key")
        if len(bundle_key) != 32:
            fail(f"bundle key is {len(bundle_key)} bytes, expected 32")
        print("   HTTP 200  32-byte key released")
    else:
        print(f"   HTTP {status}  {explain(payload)}")
        if status == 401:
            fail("the feed rejects the licence it just accepted. See the hint above; the usual "
                 "cause is the RESELLER binding missing from the deployed Worker.")
        fail("bundle key unavailable; a retry may clear a 503, a 401 will not")

    print("3. manifest")
    status, payload = request(f"{args.feed}/api/patches/{PROJECT}/manifest.json", headers)
    if status != 200:
        print(f"   HTTP {status}  {explain(payload)}")
        fail("manifest fetch failed even though the bundle key was released")
    try:
        manifest = json.loads(payload)
    except Exception:
        fail(f"manifest is not JSON: {explain(payload)}")
    entries = manifest.get("patches") or []
    names = {str(entry.get("file", "")) for entry in entries}
    print(f"   HTTP 200  {len(entries)} entries, project={manifest.get('project')}")
    missing = sorted(EXPECTED_CATALOG - names)
    if missing:
        print(f"   missing from the feed: {', '.join(missing)}")
        fail("the feed does not publish the full catalog the app expects")

    print("4. one package, verified the way the app verifies it")
    entry = entries[0]
    status, blob = request(str(entry["url"]), headers)
    if status != 200:
        print(f"   HTTP {status}  {explain(blob)}")
        fail(f"package download failed: {entry.get('file')}")
    digest = hashlib.sha256(blob).hexdigest()
    size_ok = len(blob) == int(entry.get("size", -1))
    digest_ok = digest.casefold() == str(entry.get("sha256", "")).casefold()
    print(f"   HTTP 200  {len(blob)} bytes  size={'ok' if size_ok else 'MISMATCH'}  "
          f"sha256={'ok' if digest_ok else 'MISMATCH'}  ({entry.get('file')})")
    if not (size_ok and digest_ok):
        fail("the feed serves bytes that do not match its own manifest")

    print("\nPASS: this key and device can fetch the catalog. A build with this licence will sync.")


if __name__ == "__main__":
    main()
