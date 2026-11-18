#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Coffey Labs LLC
# SPDX-License-Identifier: Apache-2.0
#
# Downloads the tools tools/check.sh uses into DIR (default ./.tools/bin),
# each at a pinned version and checked against a pinned SHA-256, so CI and
# a contributor run the same binaries. linux/amd64 only, which is what CI
# runs on; elsewhere install the same versions yourself.
#
# To move a pin: change the version and its hash together. The hashes are
# the projects' own published ones (CHECKSUMS, *.sha256sum, the release
# asset digest).
set -euo pipefail

DIR="${1:-.tools/bin}"
mkdir -p "$DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

HELM4_VERSION=v4.3.2
HELM4_SHA256=d1c0278d46beab79582d7e50f5b3dc206944ba8e577cde618513fd07daa53983
HELM3_VERSION=v3.22.1
HELM3_SHA256=896cf63684a42a723d61c980369d6e588330927deb13676ca0d85006dd6da0ea
KUBECONFORM_VERSION=v0.8.0
KUBECONFORM_SHA256=9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883
KUBE_LINTER_VERSION=v0.8.3
KUBE_LINTER_SHA256=1a6d8419b11971372971fdbc22682b684ebfb7cf1c39591662d1b6ca736c41df
HELM_UNITTEST_VERSION=1.2.1
HELM_UNITTEST_SHA256=48e86ecc1467b009630e5954375e5d8494139f73b466df5fe8c04fa45b634939

# fetch URL SHA256 FILE: download URL to $WORK/FILE and check its hash
fetch() {
  curl -fsSL --retry 3 --proto '=https' -o "$WORK/$3" "$1"
  echo "$2  $WORK/$3" | sha256sum -c --quiet -
}

fetch "https://get.helm.sh/helm-$HELM4_VERSION-linux-amd64.tar.gz" "$HELM4_SHA256" helm4.tgz
tar -xzf "$WORK/helm4.tgz" -C "$WORK" linux-amd64/helm
install -m 0755 "$WORK/linux-amd64/helm" "$DIR/helm"

fetch "https://get.helm.sh/helm-$HELM3_VERSION-linux-amd64.tar.gz" "$HELM3_SHA256" helm3.tgz
tar -xzf "$WORK/helm3.tgz" -C "$WORK" linux-amd64/helm
install -m 0755 "$WORK/linux-amd64/helm" "$DIR/helm3"

fetch "https://github.com/yannh/kubeconform/releases/download/$KUBECONFORM_VERSION/kubeconform-linux-amd64.tar.gz" \
  "$KUBECONFORM_SHA256" kubeconform.tgz
tar -xzf "$WORK/kubeconform.tgz" -C "$WORK" kubeconform
install -m 0755 "$WORK/kubeconform" "$DIR/kubeconform"

fetch "https://github.com/stackrox/kube-linter/releases/download/$KUBE_LINTER_VERSION/kube-linter-linux.tar.gz" \
  "$KUBE_LINTER_SHA256" kube-linter.tgz
tar -xzf "$WORK/kube-linter.tgz" -C "$WORK" kube-linter
install -m 0755 "$WORK/kube-linter" "$DIR/kube-linter"

fetch "https://github.com/helm-unittest/helm-unittest/releases/download/v$HELM_UNITTEST_VERSION/helm-unittest-linux-amd64-$HELM_UNITTEST_VERSION.tgz" \
  "$HELM_UNITTEST_SHA256" helm-unittest.tgz
tar -xzf "$WORK/helm-unittest.tgz" -C "$WORK" untt-linux-amd64
install -m 0755 "$WORK/untt-linux-amd64" "$DIR/helm-unittest"

echo "Tools in $DIR:"
"$DIR/helm" version --short
"$DIR/helm3" version --short
"$DIR/kubeconform" -v
"$DIR/kube-linter" version
