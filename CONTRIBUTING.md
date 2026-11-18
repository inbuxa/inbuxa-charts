# Contributing to inbuxa-charts

This repository holds the Helm chart that runs inbuxa on Kubernetes: the
mail server, the webmail and the console. Bug reports, release-candidate
reports and changes are all welcome.

## Before you start

- The chart runs the inbuxa images; it doesn't build them. A bug in the
  server, the webmail or the console belongs in
  [inbuxa-server](https://git.coffeylabs.org/inbuxa/inbuxa-server/issues),
  [inbuxa-webmail](https://git.coffeylabs.org/inbuxa/inbuxa-webmail/issues) or
  [inbuxa-admin](https://git.coffeylabs.org/inbuxa/inbuxa-admin/issues).
- The data layer (PostgreSQL, NATS, S3) is yours to bring. The chart
  connects to it and doesn't install it.
- No operator and no custom resources: a chart and plain manifests only.
- The chart is licensed under **Apache-2.0**, and a change you send is
  distributed under it. The images it runs stay under their own licences.

## Reporting a problem

Search the [issues](https://git.coffeylabs.org/inbuxa/inbuxa-charts/issues)
first. A new issue offers two forms: **Bug** for something that's wrong, and
**Release candidate report** for how an RC went on your cluster, good or bad.
Both ask for the chart version, your Kubernetes version and distribution, and
what you set in your values. Leave out passwords, keys and hostnames you'd
rather not publish.

## Sending a change

New accounts on git.coffeylabs.org can file issues but can't push or fork.
Until you have repository access, open an
[issue](https://git.coffeylabs.org/inbuxa/inbuxa-charts/issues) for the
change, or say hello on [community.coffeylabs.org](https://community.coffeylabs.org),
and attach the change to the issue as a patch:

```bash
git format-patch origin/main --stdout > my-change.patch
```

Repository access goes to volunteers we have worked with; a few good issues
or patches is the usual way in. After that you push a branch here and open a
pull request against `main`. The GitHub copy is a read-only mirror, so pull
requests opened there are not merged.

A pull request:

1. Does one thing, on a branch named for it (`fix/probe-timeout`,
   `feat/webmail-hpa`).
2. Passes `tools/check.sh` before it's pushed (see below).
3. Adds or updates a test in `charts/inbuxa/tests/` for what it changes.
4. Describes any new value in `values.yaml` and in `values.schema.json`,
   with a sensible default. The schema refuses keys it doesn't know, so a
   value missing from it can't be set at all.
5. Adds a line to `CHANGELOG.md` under **Unreleased**.

`main` is protected: a change reaches it through a pull request whose
**chart** check has passed.

## The checks

`tools/check.sh` is everything CI runs:

- `helm lint --strict` under Helm 4 and Helm 3, with each values file in
  `charts/inbuxa/ci/`
- that the values schema refuses an unknown key
- kubeconform against the three newest Kubernetes minors
- kube-linter, with every built-in check on
- helm-unittest

`tools/install-tools.sh` downloads the exact versions CI uses, checked
against pinned SHA-256 hashes, into `.tools/bin` (linux/amd64):

```bash
tools/install-tools.sh && tools/check.sh
```

To check a new set of values, add `charts/inbuxa/ci/<name>-values.yaml`;
every file there is linted, rendered and checked.

Installing on a real cluster, the mail tests and the upgrade tests live in
[inbuxa-k8s-lab](https://git.coffeylabs.org/inbuxa/inbuxa-k8s-lab).
