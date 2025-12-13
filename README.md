<div align="center">

# Kubelab

Local Kubernetes with wildcard DNS, trusted TLS, and pre-configured services.

[![Kubernetes](https://img.shields.io/badge/kubernetes-v1.28+-326CE5?style=flat&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Minikube](https://img.shields.io/badge/minikube-latest-F7B500?style=flat&logo=kubernetes&logoColor=white)](https://minikube.sigs.k8s.io/)
[![Helm](https://img.shields.io/badge/helm-v3-0F1689?style=flat&logo=helm&logoColor=white)](https://helm.sh/)
[![License](https://img.shields.io/badge/license-MIT-green.svg?style=flat)](LICENSE)

</div>

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              macOS Host                                       │
│                                                                               │
│   Browser: https://grafana.monitoring.minikube.local ────────────────┐       │
│                                                                       │       │
│   ┌─────────────────┐     ┌─────────────────────────────────────────┐│       │
│   │    dnsmasq      │     │              minikube tunnel             ││       │
│   │ *.minikube.local│────▶│          (127.0.0.1 forwarding)         ││       │
│   │   → 127.0.0.1   │     └───────────────────┬─────────────────────┘│       │
│   └─────────────────┘                         │                       │       │
│                                               ▼                       │       │
│   ┌───────────────────────────────────────────────────────────────────┘       │
│   │                                                                           │
│   │   ┌─────────────────────────────────────────────────────────────────┐    │
│   │   │                    Minikube Cluster                              │    │
│   │   │  ┌──────────────────────────────────────────────────────────┐   │    │
│   │   │  │               NGINX Ingress Controller                    │   │    │
│   │   │  │      (TLS termination via cert-manager + mkcert)          │   │    │
│   │   │  └──────────────────────────────────────────────────────────┘   │    │
│   │   │                              │                                   │    │
│   │   │    ┌─────────────────────────┼─────────────────────────┐        │    │
│   │   │    │                         │                         │        │    │
│   │   │    ▼                         ▼                         ▼        │    │
│   │   │ ┌────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────┐  │    │
│   │   │ │ ArgoCD │  │PostgreSQL│  │  Redis   │  │OpenSearch│  │ ... │  │    │
│   │   │ │ + Dex  │  │  (CNPG)  │  │          │  │+ Fluent  │  │     │  │    │
│   │   │ └────────┘  └──────────┘  └──────────┘  └──────────┘  └─────┘  │    │
│   │   │                                                                  │    │
│   │   │  ┌──────────────────────────────────────────────────────────┐   │    │
│   │   │  │              VictoriaMetrics + Grafana                    │   │    │
│   │   │  │          (Metrics, Dashboards, Alerting)                  │   │    │
│   │   │  └──────────────────────────────────────────────────────────┘   │    │
│   │   └─────────────────────────────────────────────────────────────────┘    │
│   │                                                                           │
└───┴───────────────────────────────────────────────────────────────────────────┘
```

## What's Included

- **Wildcard DNS** — `*.minikube.local` via dnsmasq
- **Trusted TLS** — mkcert CA + cert-manager, no browser warnings
- **Databases** — PostgreSQL (CloudNativePG), Redis
- **Observability** — VictoriaMetrics, Grafana, Fluent Bit, OpenSearch
- **GitOps** — ArgoCD with Dex SSO
- **Declarative Helm** — YAML-based chart deployment

## Prerequisites

### Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS (Apple Silicon) | Supported | Primary development platform |
| macOS (Intel) | Supported | Tested |
| Linux | Not tested | Should work with dnsmasq adjustments |
| Windows | Not supported | WSL2 untested |

### Required Tools

```bash
brew install minikube helm kubectl mkcert yq
```

### One-Time Setup

```bash
mkcert -install        # Install CA into system trust store
open -a Docker         # Ensure Docker Desktop is running
```

### System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU      | 4 cores | 6 cores     |
| Memory   | 8 GB    | 12 GB       |
| Disk     | 20 GB   | 40 GB       |

## Quick Start

```bash
git clone https://github.com/yourusername/kubelab.git
cd kubelab

make all              # Create cluster, configure DNS, install certs
make tunnel           # Run in separate terminal
make charts           # Deploy all services
make status           # Verify everything is running
```

Access services at `https://<service>.<namespace>.minikube.local`

## Services

### Databases

| Service | Host | Port | Credentials |
|---------|------|------|-------------|
| PostgreSQL (RW) | `postgresql.minikube.local` | 5432 | `developer` / `LocalDev123!` |
| PostgreSQL (RO) | `postgresql.minikube.local` | 5433 | `developer` / `LocalDev123!` |
| Redis | `redis.minikube.local` | 6379 | `LocalDev123!` |

```bash
# PostgreSQL
postgresql://developer:LocalDev123!@postgresql.minikube.local:5432/devdb

# Redis
redis://:LocalDev123!@redis.minikube.local:6379
```

### Web UIs

| Service | URL | Credentials |
|---------|-----|-------------|
| ArgoCD | https://console.argocd.minikube.local | SSO via Dex |
| Grafana | https://grafana.monitoring.minikube.local | `admin` / `LocalDev123!` |
| OpenSearch | https://dashboards.opensearch.minikube.local | `admin` / `LocalDev123!` |
| RustFS | https://console.rustfs.minikube.local | `rustfsadmin` / `rustfsadmin` |

### SSO Users (Dex)

| Email | Password | Role |
|-------|----------|------|
| `admin@minikube.local` | `admin123` | Administrator |
| `developer@minikube.local` | `dev123` | Developer (read-only) |

## Commands

### Setup

| Command | Description |
|---------|-------------|
| `make all` | Full setup: cluster, DNS, certificates |
| `make cluster` | Create Minikube cluster only |
| `make dns` | Configure wildcard DNS |
| `make certs` | Install cert-manager with mkcert CA |
| `make clean` | Delete everything |

### Daily Use

| Command | Description |
|---------|-------------|
| `make tunnel` | Start tunnel (run in separate terminal) |
| `make start` | Start stopped cluster |
| `make stop` | Stop cluster |
| `make status` | Show cluster status |
| `make dashboard` | Open Kubernetes Dashboard |

### Charts

| Command | Description |
|---------|-------------|
| `make charts` | Deploy all enabled charts |
| `make chart-<name>` | Deploy specific chart |
| `make charts-list` | List available charts |

## Configuration

```bash
cp config/.env.example config/.env
```

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `minikube` | Minikube profile name |
| `CPUS` | `4` | CPU cores |
| `MEMORY` | `8192` | Memory in MB |
| `DOMAIN` | `minikube.local` | Base domain |

### GitLab Integration (Optional)

For ArgoCD GitOps, add to `config/.env`:

```bash
GITLAB_HOST=gitlab.example.com
GITLAB_ORG=your-org
GITLAB_REPO=gitops-apps
GITLAB_TOKEN=glpat-xxxxxxxxxxxx
```

## Adding Charts

Create a YAML file in `charts/`:

```yaml
enabled: true

chart:
  repository: https://charts.bitnami.com/bitnami
  name: nginx
  version: ""

release:
  name: my-nginx
  namespace: web

ingress:
  enabled: true
  name: nginx           # → nginx.web.minikube.local
  serviceName: my-nginx
  servicePort: 80

values:
  replicaCount: 1
```

Deploy with `make chart-my-nginx`.

For manifest-only deployments (no Helm chart), omit `chart.repository` and `chart.name`, use `postInstall` for raw YAML.

## Troubleshooting

### Services not accessible

```bash
make tunnel                          # Must be running
kubectl get pods -n ingress-nginx    # Check ingress controller
```

### DNS not resolving

```bash
sudo brew services list | grep dnsmasq
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
dig +short test.minikube.local @127.0.0.1
```

### Certificate errors

```bash
mkcert -install
kubectl get clusterissuer mkcert-issuer
kubectl get certificates -A
```

### Firefox certificate warning

Set `security.enterprise_roots.enabled = true` in `about:config`.

## Architecture

### DNS Flow

```
Browser → dnsmasq (*.minikube.local → 127.0.0.1)
       → minikube tunnel → NGINX Ingress → Service → Pod
```

### Certificate Chain

```
mkcert CA (system trust) → cert-manager ClusterIssuer → Certificate → TLS Secret
```

### Logs

```
Container → Fluent Bit → OpenSearch → Dashboards
```

### Metrics

```
Exporters → VMAgent → VMSingle → Grafana
```

## License

MIT License - see [LICENSE](LICENSE) for details.
