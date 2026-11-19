#!/bin/sh
# SPDX-FileCopyrightText: 2026 Coffey Labs LLC
# SPDX-License-Identifier: Apache-2.0
#
# K-C7: the address outbound mail leaves from, from a pod placed like the mta
# pods, against the addresses expected (the ones with PTR records and in
# SPF). The answer goes on the mta Deployment as an event: Normal when it
# matches, Warning when it doesn't or can't be learned. It never fails, so it
# never holds up an install or an upgrade. Only sh, sed, tr and curl: the
# image has nothing more.
#
# CHECK_URL answers a GET with the caller's address as plain text.
set -u
sa=/var/run/secrets/kubernetes.io/serviceaccount

event() { # <Normal|Warning> <reason> <message>
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  message=$(printf '%s' "$3" | sed 's/\\/\\\\/g; s/"/\\"/g')
  body=$(printf '{"apiVersion":"v1","kind":"Event","metadata":{"generateName":"%s.","namespace":"%s"},"involvedObject":{"apiVersion":"apps/v1","kind":"Deployment","name":"%s","namespace":"%s"},"type":"%s","reason":"%s","message":"%s","firstTimestamp":"%s","lastTimestamp":"%s","count":1,"source":{"component":"inbuxa-egress-check"}}' \
    "$DEPLOYMENT" "$NAMESPACE" "$DEPLOYMENT" "$NAMESPACE" "$1" "$2" "$message" "$now" "$now")
  echo "$1 $2: $3"
  curl -fsS -o /dev/null --cacert "$sa/ca.crt" -H "Authorization: Bearer $(cat "$sa/token")" \
    -H 'Content-Type: application/json' -X POST -d "$body" \
    "https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE/events" ||
    echo "couldn't record the event on deployment/$DEPLOYMENT"
}

seen=$(curl -fsS -m 20 "$CHECK_URL" 2>/dev/null | tr -d ' \r\n')
case "$seen" in
  "" | *[!0-9a-fA-F.:]*)
    event Warning EgressUnknown "Couldn't learn the address outbound mail leaves from: $CHECK_URL gave no address. Expected one of: $EXPECTED."
    exit 0
    ;;
esac
for address in $EXPECTED; do
  if [ "$address" = "$seen" ]; then
    event Normal EgressAddress "Outbound mail leaves from $seen, as expected."
    exit 0
  fi
done
event Warning EgressMismatch "Outbound mail leaves from $seen, which is not one of the expected addresses ($EXPECTED). Receivers check its reverse DNS and SPF: mail may be refused or marked as spam."
exit 0
