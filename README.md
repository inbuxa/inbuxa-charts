# inbuxa-charts

The Helm chart for running inbuxa on Kubernetes: the mail server, the
webmail and the console, against a PostgreSQL, NATS and S3 you provide.

**Status: in development.** The chart is being built for inbuxa 27.1 and
doesn't install anything yet. Release candidates start with `27.1.0-rc.1`.

- `charts/inbuxa`: the chart, its values schema and its tests
- `tools/check.sh`: every check CI runs; see [CONTRIBUTING.md](CONTRIBUTING.md)
- [CHANGELOG.md](CHANGELOG.md)

Installs on real clusters, the mail tests and the upgrade tests are in
[inbuxa-k8s-lab](https://git.coffeylabs.org/inbuxa/inbuxa-k8s-lab). The guide
is at [docs.inbuxa.org](https://docs.inbuxa.org/).

Licensed under the [Apache License 2.0](LICENSE). The images the chart runs
are licensed separately.
