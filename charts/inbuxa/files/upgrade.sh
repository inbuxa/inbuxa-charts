#!/bin/sh
# SPDX-FileCopyrightText: 2026 Coffey Labs LLC
# SPDX-License-Identifier: Apache-2.0
#
# The chart's pre-upgrade run, on the new server image, before Helm rolls
# out the new pods. It asks the server what the upgrade does to the store
# (--upgrade-plan), refuses a layout change nobody acknowledged, stops the
# server pods when a step needs every node stopped, and upgrades the store
# (--upgrade-store). Only sh, sed and curl: the image has nothing more.
#
# From the Job: RELEASE, NAMESPACE, DEPLOYMENTS (space-separated),
# ACKNOWLEDGE_LAYOUT, STOP_SERVERS (true/false), STOP_WAIT_SECONDS.
set -u

config=/etc/inbuxa/config.json

# The server logs to stdout too; the plan is the one line of JSON
out=$(inbuxa --upgrade-plan --config "$config")
code=$?
plan=$(printf '%s\n' "$out" | grep '^{' | tail -n 1)
echo "Plan: $plan"

case $code in
  0)
    echo "The store needs no layout change: nothing to do before the rollout."
    exit 0
    ;;
  3 | 4) ;;
  2)
    echo "A newer release has changed this store's layout. This release can't run on it:" \
      "upgrade to that release, or restore the backup taken before it." >&2
    exit 1
    ;;
  *)
    echo "The server couldn't plan the upgrade (exit $code); its message is above." >&2
    exit 1
    ;;
esac

from=$(printf '%s' "$plan" | sed -n 's/.*"store":\([0-9]*\).*/\1/p')
target=$(printf '%s' "$plan" | sed -n 's/.*"target":\([0-9]*\).*/\1/p')

if [ "${ACKNOWLEDGE_LAYOUT:-0}" != "$target" ]; then
  cat >&2 <<MSG
This upgrade changes the store's layout from version $from to $target, which
older releases can't read: going back means restoring a backup taken before
it. Take one now, then upgrade again with

  --set server.upgrade.acknowledgeLayout=$target

Nothing has been changed.
MSG
  exit 1
fi

if [ "$code" = 4 ]; then
  if [ "${STOP_SERVERS:-true}" != true ]; then
    echo "A layout step needs every server pod stopped, and stopServers is off:" \
      "the upgrade waits for them to stop, and fails if they don't."
  else
    echo "A layout step needs every server pod stopped: scaling $DEPLOYMENTS to 0. Mail is down until the rollout."
    api="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
    sa=/var/run/secrets/kubernetes.io/serviceaccount
    token=$(cat "$sa/token")
    kube() {
      curl -fsS --cacert "$sa/ca.crt" -H "Authorization: Bearer $token" "$@"
    }
    for deployment in $DEPLOYMENTS; do
      kube -X PATCH -H 'Content-Type: application/merge-patch+json' \
        -d '{"spec":{"replicas":0}}' \
        "$api/apis/apps/v1/namespaces/$NAMESPACE/deployments/$deployment/scale" >/dev/null \
        || { echo "Couldn't scale $deployment to 0." >&2; exit 1; }
    done
    selector="app.kubernetes.io/instance%3D$RELEASE,app.kubernetes.io/component%3Dserver"
    waited=0
    # The API server pretty-prints for curl: "items": [] with a space
    until kube "$api/api/v1/namespaces/$NAMESPACE/pods?labelSelector=$selector" | grep -Eq '"items": *\[ *\]'; do
      if [ "$waited" -ge "${STOP_WAIT_SECONDS:-300}" ]; then
        echo "The server pods didn't stop within ${STOP_WAIT_SECONDS:-300}s." >&2
        exit 1
      fi
      sleep 5
      waited=$((waited + 5))
    done
    echo "Every server pod has stopped (${waited}s)."
  fi
fi

exec inbuxa --upgrade-store --config "$config"
