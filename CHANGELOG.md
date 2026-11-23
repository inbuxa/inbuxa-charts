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
  `mta` (as front, plus outbound delivery) and `core` (everything; two
  replicas that take turns with the scheduler and the alerts, server
  27.1-rc.40). The data store is a value, written as `config.json`; its
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
  `webmail.existingSecret`, mounted as files rather than set in its
  environment; `webmail.previousAppSecret` reads the old app secret during a
  rotation. The webmail checks its read-only root at start (`IMMUTABLE`).
  Every server pod is told both addresses, so it registers them as OAuth
  clients; the webmail's client secret reaches the server as a mounted file
  too (`INBUXA_WEBMAIL_CLIENT_SECRET_FILE`), never the environment.
- `routes`: the server's, the webmail's and the console's public addresses,
  each by host name, as Gateway API HTTPRoutes or one Ingress.
- The server counts clients by the address the ingress or gateway and the
  webmail pass on (`INBUXA_HTTP_USE_FORWARDED`), so failed sign-ins and
  anonymous requests aren't charged to the proxy: without it, enough wrong
  passwords between all users would ban the ingress for everyone.
  `server.trustedProxies` lists the proxies when the pod network isn't a
  private range. Needs server 27.1-rc.32; older servers ignore it.
- Certificates for the mail ports (`server.certificates`): TLS Secrets
  (`secrets`, or `certManager` to have the chart ask cert-manager for one)
  mounted in every server pod and reread within about two minutes of a
  renewal, with no restart; and `acmeHosts`, which routes the server's own
  ACME HTTP-01 challenges for the mail names to it. Needs server
  27.1-rc.33.
- Mail out from a known address (`server.egress`): with
  `expectedAddresses` and `checkUrl` set, a Job placed like the mta pods
  asks which address it leaves from after each install and upgrade, and
  records the answer on the mta Deployment as an event, a Warning when it
  isn't one of the expected addresses. It never fails an install. Its token
  may create events and nothing else. `podLabels` on each server group, for
  an egress gateway that selects the mta pods.
- Mail in through a load balancer that sends PROXY protocol v2
  (`server.services.mail.proxyProtocol`, off by default): the mail Service
  sends each port to a second listener in the pods that takes the client's
  address from the PROXY header, believed only from `trustedNetworks`, the
  load balancer's own addresses. It needs `externalTrafficPolicy: Local`, and
  server 27.1-rc.32.
- A pre-flight check before each server pod starts (`server.check`, on by
  default): an init container runs `inbuxa --check`, which opens the data
  store, writes, reads and deletes a small object in the blob store, and
  connects to NATS. A pod that can't use one stays in `Init:Error`, and its
  status names the part and why. The server container keeps its last log
  lines as its termination message too. Needs server 27.1-rc.33: an older
  server doesn't know `--check`.
- `tools/docs-pages.py --out <dir>` writes the docs' generated Kubernetes
  pages: the values reference, the Services and their ports, what each
  network policy lets in and out, and the alerts, from `helm template` with
  `ci/docs-values.yaml`. CI builds them, so a change that breaks one fails.
- `charts/inbuxa/VALUES.md`, every value with its default and what the
  schema allows, generated from values.yaml and the schema by
  `tools/values-reference.py`; CI fails when it's out of date. The schema
  checks resources (requests and limits as quantities) and annotation and
  node-selector maps (strings) too, and `tools/bad-values` holds values the
  chart must refuse before anything is applied, each for a stated reason.
- The server's, the webmail's and the console's `publicUrl` must be
  `https://`; plain `http://` is refused.
- Backups and store checks on a schedule. `server.backup` exports the
  whole store nightly to an S3 bucket (`inbuxa --export s3://...`), streamed
  while the server runs, into a folder per export with `export.json`
  written last; `inbuxa --import s3://bucket/prefix` restores the newest
  finished one. `server.storeCheck` runs a quick check nightly and a full
  one weekly; a check that finds problems fails its Job. With the metrics
  rules and kube-state-metrics, InbuxaBackupMissing and
  InbuxaStoreCheckFailed alert on them. Needs server 27.1-rc.34.
- Metrics (`server.metrics`, off by default). `prometheus`: every server
  pod serves `/metrics/prometheus` behind a username and a password the pods
  read as a file, and a headless Service lists them all, with a
  ServiceMonitor that scrapes each pod and labels its group. `rules`:
  PrometheusRules for a pod down, a cluster lease not renewed, a large or
  stuck queue, deliveries bouncing, a certificate about to expire, a slow
  data store, and (from kube-state-metrics) restarts and flapping readiness.
  `otlp`: push to an OpenTelemetry collector, the token from a Secret read as
  a file. `grafanaDashboard`: a dashboard for Grafana's sidecar.
  `networkPolicy.metricsFrom` lets Prometheus through when `httpFrom` is
  narrowed. Needs server 27.1-rc.34.
- `networkPolicy`, on by default: every pod starts from deny all, in and
  out, and gets only what it needs. The server takes mail on its listeners
  from anywhere and connects anywhere; `networkPolicy.httpFrom` and
  `networkPolicy.serverEgress` narrow its HTTP port and its egress. The
  webmail reaches DNS, the server and the web (`networkPolicy.webmailInternet`
  for remote images); the console reaches nothing. The seed and upgrade
  Jobs, which run before the release's own policies exist on a first
  install, are covered by copies of the two they need, run as hooks first.
  Every pod passes Pod Security "restricted", tested in enforce mode.
- Releases (K-C13): a `v*` tag releases the chart from `release/suite.yaml`,
  with the server, webmail and console images pinned by digest once their
  signatures check out; the chart pushed to GHCR and the Gitea registry and
  signed keyless with cosign; rendered manifests; a minisign-signed
  `SHA256SUMS`. `tools/verify-release.sh` checks all of it.
- GitOps (K-C14): `generateSecrets: false` makes the chart refuse to render
  without `webmail.existingSecret` and
  `server.metrics.prometheus.existingSecret`, for Argo CD and
  `helm template | kubectl apply`, which can't read back the secrets the
  chart makes and would replace them on every sync. Every hook also carries
  Argo CD's own annotations, so the order there is safe: the hook network
  policies, then the upgrade check (nothing to do on a new store), then the
  seed, which Argo runs on every sync and which does nothing on a seeded
  store.
- `server.shutdownDelaySeconds` (5 by default): a stopping server pod keeps
  serving that long, with a `preStop` sleep, while Kubernetes takes it out
  of the Services, so a request routed to it in that moment isn't refused.
