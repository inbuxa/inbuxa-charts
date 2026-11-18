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
- The server, as three Deployments: `front` (client protocols and web),
  `mta` (as front, plus outbound delivery) and `core` (everything, exactly
  one replica). The data store is a value, written as `config.json`; its
  secrets are Secrets mounted under `/etc/inbuxa/secrets`.
- Pods that run as a non-root user with every capability dropped, a
  read-only root filesystem and the RuntimeDefault seccomp profile. They
  listen on the standard mail ports through the namespaced sysctl
  `net.ipv4.ip_unprivileged_port_start`, which Pod Security "restricted"
  allows.
- A `mail` LoadBalancer Service (front and mta, client addresses kept) and an
  `http` ClusterIP Service (front and core), PodDisruptionBudgets, and
  spreading across nodes and zones.
- `server.seed`: the new store's setup (domain, administrator, blob store,
  coordinator, roles), applied once on install by a pre-install Job running
  the server's `--seed`, before any server pod starts.
- `server.upgrade`: before an upgrade or rollback rolls out, a Job on the
  new image asks the server what it does to the store (`--upgrade-plan`).
  A layout change waits for `upgrade.acknowledgeLayout`. When a layout step
  can't run with older pods up, the server Deployments are scaled to 0
  first, which a rolling update can't do. Then `--upgrade-store` upgrades
  the store.
- `webmail` and `console`, off by default: Deployments, Services, optional
  autoscalers and PodDisruptionBudgets, read-only root filesystems. The
  webmail keeps sessions in sealed cookies, so any replica serves any
  request, and signs in through the server's page. Its app and OAuth client
  secrets are a Secret the chart makes (kept across upgrades) or
  `webmail.existingSecret`. Every server pod is told both addresses, so it
  registers them as OAuth clients.
- `routes`: the server's, the webmail's and the console's public addresses,
  each by host name, as Gateway API HTTPRoutes or one Ingress.
