#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Coffey Labs LLC
# SPDX-License-Identifier: Apache-2.0
#
# Every check CI runs on the chart, in the order it runs them. Run it before
# you push: tools/install-tools.sh puts the pinned tools in .tools/bin, and
# this script uses them from there when they're present.
#
#   tools/install-tools.sh && tools/check.sh
set -euo pipefail

cd "$(dirname "$0")/.."
[ -d .tools/bin ] && PATH="$PWD/.tools/bin:$PATH"

CHART=charts/inbuxa
# The three newest Kubernetes minors (support matrix). kubeconform's schema
# set has to have them: a new minor is added here once it does.
KUBE_VERSIONS=(1.35.0 1.36.0 1.37.0)
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

step() { printf '\n== %s\n' "$*"; }

for helm in helm helm3; do
  step "$helm lint ($($helm version --short))"
  for values in "$CHART"/ci/*-values.yaml; do
    $helm lint --strict "$CHART" -f "$values"
  done
done

step "the values schema rejects a key it doesn't know"
if helm lint --strict "$CHART" -f "$CHART/ci/defaults-values.yaml" --set notAValue=1 >"$OUT/reject.log" 2>&1; then
  echo "!! an unknown value was accepted" >&2
  exit 1
fi
grep -q "notAValue" "$OUT/reject.log" || {
  echo "!! refused, but not over the unknown value:" >&2
  cat "$OUT/reject.log" >&2
  exit 1
}
echo "refused, as it should be"

for values in "$CHART"/ci/*-values.yaml; do
  name="$(basename "$values" -values.yaml)"
  for kube in "${KUBE_VERSIONS[@]}"; do
    step "kubeconform: $name values on Kubernetes $kube"
    helm template ci "$CHART" -n inbuxa -f "$values" --kube-version "$kube" >"$OUT/$name-$kube.yaml"
    kubeconform -strict -summary -kubernetes-version "$kube" \
      -schema-location default "$OUT/$name-$kube.yaml"
  done
  step "kube-linter: $name values"
  rendered="$OUT/$name-${KUBE_VERSIONS[-1]}.yaml"
  if grep -q '^kind:' "$rendered"; then
    kube-linter lint --config .kube-linter.yaml "$rendered"
  else
    # kube-linter treats "no objects" as a failure
    echo "nothing rendered, nothing to lint"
  fi
done

step "helm-unittest"
helm-unittest --strict "$CHART"

printf '\nAll checks passed.\n'
