#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Coffey Labs LLC
# SPDX-License-Identifier: Apache-2.0
#
# Checks a chart release the way someone installing it would, from nothing
# but what was published (K-C13):
#
#   1. the chart in the registry carries a signature from this repository's
#      release workflow, made from a release tag;
#   2. the chart pulled from there is the one SHA256SUMS lists, and
#      SHA256SUMS is signed with the inbuxa release key (minisign);
#   3. the rendered manifests tarball is the one SHA256SUMS lists;
#   4. every image the chart pins, by digest, is signed by the workflow of
#      the repository it comes from.
#
#   tools/verify-release.sh 27.1.0-rc.1
#
# Needs cosign, helm (3 or 4), minisign, curl, jq and sha256sum. Options:
#   --chart oci://REGISTRY/PATH   where the chart is (oci://ghcr.io/inbuxa/charts)
#   --files DIR                   SHA256SUMS and the tarball are in DIR, not
#                                 downloaded from the release page
#   --test                        a test release (0.0.0-test.N): signed from
#                                 main rather than a tag, and SHA256SUMS may
#                                 be unsigned
set -euo pipefail

CHART_REF=oci://ghcr.io/inbuxa/charts
FILES=""
TEST=false
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --chart) CHART_REF="$2"; shift 2 ;;
    --files) FILES="$2"; shift 2 ;;
    --test) TEST=true; shift ;;
    -h|--help) sed -n '5,26p' "$0"; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) VERSION="$1"; shift ;;
  esac
done
[ -n "$VERSION" ] || { echo "usage: $0 [--chart oci://...] [--files DIR] [--test] VERSION" >&2; exit 2; }

# The release key that signs every inbuxa release's SHA256SUMS
MINISIGN_KEY=RWS1yFYwVuJ7MGJTZXLbhv9+hrEsjrC8Zg+7WmPlM86Sjy0qF/xkoCKq
ISSUER=https://token.actions.githubusercontent.com
if $TEST; then
  CHART_ID='^https://github\.com/inbuxa/inbuxa-charts/\.github/workflows/release\.yml@refs/heads/main$'
else
  CHART_ID='^https://github\.com/inbuxa/inbuxa-charts/\.github/workflows/release\.yml@refs/tags/v.+$'
fi
# Each image is signed by its own repository's sign.yml
image_id() {
  case "$1" in
    */inbuxa-server@*) echo '^https://github\.com/inbuxa/inbuxa-server/\.github/workflows/sign\.yml@refs/(tags/v.+|heads/main)$' ;;
    */inbuxa-webmail@*) echo '^https://github\.com/inbuxa/inbuxa-webmail/\.github/workflows/sign\.yml@refs/(tags/inbuxa-v.+|heads/main)$' ;;
    */inbuxa-admin@*) echo '^https://github\.com/inbuxa/inbuxa-admin/\.github/workflows/sign\.yml@refs/(tags/v.+|heads/main)$' ;;
    *) return 1 ;;
  esac
}

for t in cosign helm minisign curl jq sha256sum; do
  command -v "$t" >/dev/null || { echo "needs $t" >&2; exit 2; }
done
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ok() { printf '  ok  %s\n' "$*"; }

TARBALL="inbuxa-$VERSION-manifests.tar.gz"
if [ -z "$FILES" ]; then
  # 27.1.0-rc.1 is tagged v27.1-rc.1; 27.1.3 is v27.1.3; 27.1.0 is v27.1
  core="${VERSION%%-*}"; pre="${VERSION#"$core"}"
  case "$core" in *.0) tag="v${core%.0}$pre" ;; *) tag="v$core$pre" ;; esac
  base="https://git.coffeylabs.org/inbuxa/inbuxa-charts/releases/download/$tag"
  FILES="$WORK/files"; mkdir -p "$FILES"
  for f in SHA256SUMS SHA256SUMS.minisig "$TARBALL"; do
    curl -fsSL --proto '=https' -o "$FILES/$f" "$base/$f"
  done
fi

echo "inbuxa chart $VERSION"

# 1. The chart's signature, by digest
ref="${CHART_REF#oci://}/inbuxa"
digest="$(helm pull "$CHART_REF/inbuxa" --version "$VERSION" -d "$WORK" 2>&1 | sed -n 's/^Digest: //p')"
[ -n "$digest" ] || { echo "couldn't pull $CHART_REF/inbuxa $VERSION" >&2; exit 1; }
cosign verify "$ref@$digest" --certificate-oidc-issuer "$ISSUER" \
  --certificate-identity-regexp "$CHART_ID" >/dev/null 2>&1 ||
  { echo "FAIL: $ref@$digest has no signature from the release workflow" >&2; exit 1; }
ok "chart $ref@$digest is signed by inbuxa-charts' release workflow"

# 2. SHA256SUMS: signed, and listing the chart
if [ -f "$FILES/SHA256SUMS.minisig" ]; then
  minisign -Vqm "$FILES/SHA256SUMS" -P "$MINISIGN_KEY" ||
    { echo "FAIL: SHA256SUMS isn't signed with the inbuxa release key" >&2; exit 1; }
  ok "SHA256SUMS is signed with the inbuxa release key"
elif $TEST; then
  echo "  --  SHA256SUMS is unsigned (a test release)"
else
  echo "FAIL: no SHA256SUMS.minisig" >&2; exit 1
fi
cp "$FILES/SHA256SUMS" "$WORK/SHA256SUMS"
cp "$FILES/$TARBALL" "$WORK/$TARBALL"
(cd "$WORK" && sha256sum -c --quiet SHA256SUMS) ||
  { echo "FAIL: a file doesn't match SHA256SUMS" >&2; exit 1; }
for f in "inbuxa-$VERSION.tgz" "$TARBALL"; do
  grep -q "  $f\$" "$WORK/SHA256SUMS" || { echo "FAIL: SHA256SUMS doesn't list $f" >&2; exit 1; }
done
ok "the chart and $TARBALL match SHA256SUMS"

# 4. Every image the chart pins
mapfile -t images < <(tar -xzOf "$WORK/inbuxa-$VERSION.tgz" inbuxa/values.yaml |
  awk '/^  image:/{r=""} /^    repository:/{r=$2} /^    digest:/{gsub(/"/,"",$2); if (r != "" && $2 != "") print r "@" $2}')
[ "${#images[@]}" -eq 3 ] || { echo "FAIL: expected 3 pinned images, found ${#images[@]}" >&2; exit 1; }
for img in "${images[@]}"; do
  id="$(image_id "$img")" || { echo "FAIL: $img isn't an inbuxa image" >&2; exit 1; }
  cosign verify "$img" --certificate-oidc-issuer "$ISSUER" \
    --certificate-identity-regexp "$id" >/dev/null 2>&1 ||
    { echo "FAIL: $img has no signature from its repository's workflow" >&2; exit 1; }
  ok "image $img is signed"
done

echo "all checks passed"
