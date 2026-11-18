# Changelog

All notable changes to the inbuxa chart.

Chart versions follow the inbuxa suite: release candidates `27.1.0-rc.N`,
then `27.1.0`. Each release says which server, webmail and console images it
runs, pinned by digest.

## Unreleased

### Added
- The repository: the chart's layout, a values schema that refuses unknown
  keys, and CI (`helm lint` under Helm 4 and 3, kubeconform against
  Kubernetes 1.35 to 1.37, kube-linter, helm-unittest).
