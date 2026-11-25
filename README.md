# mps-services-monitoring

A self-contained Docker Compose monitoring stack for **logs + metrics**:

- **Prometheus** `v3.12.0` — metrics storage & querying
- **Loki** `3.7.2` — log storage & querying
- **Grafana** `13.0.2` — dashboards, with pre-provisioned Prometheus & Loki datasources and an overview dashboard

An optional **Wazuh** `5.0.0-beta5` SIEM (manager, indexer, dashboard) can be
added via the `wazuh` compose profile — see [Wazuh SIEM (optional)](#wazuh-siem-optional).
Deployed by `odem.services.monitoring`; log shipping into Loki is handled by
the separate `odem.alloy` stack.

Core services persist their data to bind-mounted host directories; the
optional Wazuh SIEM uses Docker-managed named volumes.

## Install

| Method | Description |
|---|---|
| Default | `bootstrap.sh` clones to the system-wide mps repo dir and runs `install.sh` |
| Ansible | can be used by installing via the `odem.services.monitoring` role of [odem-services](https://github.com/my-perfect-system-ansible/odem-services) |
| Standalone | clone the repo, then run `./install.sh` inside it |

### Install (Default)

```bash
curl -fsSL https://raw.githubusercontent.com/my-perfect-system/mps-services-monitoring/main/bootstrap.sh | bash
```

All methods install OS packages best-effort, seed `.env` from `.env.example`,
materialize the service configs from their `.example` siblings (only-if-absent),
run `scripts/setup.sh` (set `MPS_MONITORING_ENABLE_SETUP=0` to skip) and start
the compose stack (`MPS_MONITORING_ENABLE_SERVICE=0` to skip); one clone per
host (`${MPS_REPO_DIR:-/srv/repo/github/my-perfect-system/mps}`), shared by
all users.

## Layout

```
.
├── docker-compose.yml
├── .env / .env.example           # bind IP + ports + versions + Wazuh creds
├── scripts/
│   ├── setup.sh                  # core data dirs + chowns (idempotent)
│   ├── wazuh-setup.sh            # one-time Wazuh setup (certs + sysctl)
│   ├── wazuh-certs-tool.sh       # vendored cert tool (generated, tracked)
│   └── wazuh-certificates-conf.sh# vendored upstream helper (unmodified)
└── services/
    ├── prometheus/
    │   ├── prometheus.yml(.example)   # scrape config (self-scrape by default)
    │   └── data/                      # TSDB
    ├── loki/
    │   ├── loki-config.yml(.example)
    │   └── data/                      # chunks, tsdb, compactor, rules
    ├── grafana/
    │   ├── grafana.ini(.example)
    │   ├── provisioning/             # datasources + dashboards
    │   ├── dashboards/overview.json
    │   └── data/
    └── wazuh/                        # profile "wazuh" (optional)
        ├── config.yml                # tracked — cert-tool node config
        ├── config/                   # gitignored — generated certs
        └── wazuh-certificates/       # gitignored — cert-tool output
```

## First-time setup

Bind-mounted data directories must be owned by the UID each container runs as before the first `docker compose up`, otherwise Loki/Grafana will fail with `permission denied` while creating subdirectories. Run the included setup script (done automatically by `install.sh`):

```bash
./scripts/setup.sh
```

It runs `sudo chown -R` on each data directory:

| Path                | Owner     | Why                                     |
|---------------------|-----------|-----------------------------------------|
| `services/prometheus/data` | `65534:65534` | Prometheus runs as the unprivileged `nobody` user |
| `services/loki/data`       | `10001:10001` | `grafana/loki` image runs as UID 10001 |
| `services/grafana/data`    | `472:472`    | `grafana/grafana` image runs as UID 472 |

The script is idempotent — running it again does not reset your data.

## Bring the stack up

```bash
docker compose up -d
```

Endpoints (default `BIND_IP=127.0.0.1`):

| Service     | URL                              |
|-------------|----------------------------------|
| Grafana     | http://127.0.0.1:3000            |
| Prometheus  | http://127.0.0.1:9090            |
| Loki        | http://127.0.0.1:3100            |

Grafana login: `admin` / `admin` (change in `.env` and re-create the container, or change from the UI on first login).

## Wazuh SIEM (optional)

The stack ships an optional [Wazuh](https://wazuh.com) 5.x SIEM (manager,
indexer, dashboard), started only when the `wazuh` compose profile is enabled.
It is agent-based: the manager receives events from Wazuh agents running on the
hosts you want to monitor, the indexer stores the alerts, and the dashboard
presents them.

It is off by default. Enabling it adds roughly 3 GB of RAM usage (the indexer
alone reserves a 1 GB JVM heap, tunable via `WAZUH_INDEXER_HEAP`).

### First-time setup

The Wazuh containers mount TLS certificates that are not tracked in git.
Generate them once with:

```bash
./scripts/wazuh-setup.sh
```

It is idempotent and does the following:

1. Generates the deployment TLS certificates with the vendored
   `scripts/wazuh-certs-tool.sh` (built from `wazuh/wazuh-installation-assistant`
   `v5.0.0-beta5`) — **never regenerated**, since regenerating invalidates the
   TLS trust between the containers.
2. Persists `vm.max_map_count=262144` (required by the Wazuh indexer).

### Enable and start

Set the profile in `.env` (`install.sh` does this when run with
`MPS_MONITORING_ENABLE_WAZUH=1`), then bring the stack up:

```env
COMPOSE_PROFILES=wazuh
```

```bash
docker compose up -d
```

### Endpoints

| Service          | URL / port                                          |
|------------------|-----------------------------------------------------|
| Wazuh dashboard  | `https://<BIND_IP>:<WAZUH_DASHBOARD_PORT>`          |
| Wazuh API        | `https://<BIND_IP>:<WAZUH_API_PORT>`                |
| Agent events     | `<BIND_IP>:<WAZUH_AGENT_PORT>` (TCP)                |
| Agent enrollment | `<BIND_IP>:<WAZUH_ENROLLMENT_PORT>` (TCP)           |
| Manager TLS      | `<BIND_IP>:<WAZUH_TLS_PORT>` (TCP)                   |
| Syslog           | `<BIND_IP>:<WAZUH_SYSLOG_PORT>` (UDP)                |

Log in to the dashboard as `admin` / `admin`. The 5.0 beta images ship the
OpenSearch demo credentials and also keep the demo indexer users — rotate or
remove them before exposing the dashboard. The internal service accounts are
configurable via `WAZUH_MANAGER_INDEXER_*` and `WAZUH_DASHBOARD_*` in `.env`;
changing them there requires the matching indexer user database.

### Prerequisites

- The agent / enrollment / API ports must be reachable from the hosts running
  Wazuh agents (open them in the firewall and set `BIND_IP` accordingly).
- `vm.max_map_count` must be at least `262144` (set by `scripts/wazuh-setup.sh`).
- The dashboard serves https with a self-signed certificate, so browsers warn.
- `WAZUH_DASHBOARD_PORT` defaults to `443`; change it (e.g. `8443`) if another
  service already binds `443` (a reverse proxy, etc.).
- These are **pre-release (5.0 beta) images**; pin a GA tag once available.

## Adding Prometheus scrape targets

Edit `services/prometheus/prometheus.yml` and add a new job under `scrape_configs`. Reload Prometheus without a restart:

```bash
curl -X POST http://127.0.0.1:9090/-/reload
```

A template block is included at the bottom of `prometheus.yml`.

## Exposing on a different IP

Edit `.env`:

```env
BIND_IP=0.0.0.0         # all interfaces
BIND_IP=192.168.1.10     # specific host IP
```

Then `docker compose up -d` (or `docker compose up -d --force-recreate`).

## Notes

- Data persists on the host under each service's `data/` directory. Remove the directory to reset state.
- Retention: Prometheus `15d`, Loki `14d` (adjust in their respective configs).
- The overview dashboard auto-loads via provisioning under the **Overview** folder.
- To stop the stack cleanly: `docker compose down` (add `-v` to also remove Docker-managed named volumes; bind-mounts are unaffected).