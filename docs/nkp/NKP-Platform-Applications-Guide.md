# NKP Platform Applications Guide

> **Reference Documentation:** `/Users/deepak/Documents/NKP/Nutanix-Kubernetes-Platform-v2_17.pdf`
>
> **Related Document:** [NKP Sizing & Scale Guide](./NKP-Sizing-Scale-Guide.md)
>
> **Last Updated:** January 2026

---

## Table of Contents

1. [Overview](#overview)
2. [Platform Applications by Category](#platform-applications-by-category)
3. [Edition Availability Matrix](#edition-availability-matrix)
4. [Core Platform Applications](#core-platform-applications)
5. [Observability Stack](#observability-stack)
6. [Security & Policy Applications](#security--policy-applications)
7. [Networking Applications](#networking-applications)
8. [Storage & Data Services](#storage--data-services)
9. [Resource Requirements Summary](#resource-requirements-summary)
10. [Scaling Platform Applications](#scaling-platform-applications)
11. [High Availability Configurations](#high-availability-configurations)
12. [Tuning & Optimization](#tuning--optimization)
13. [Troubleshooting Common Issues](#troubleshooting-common-issues)

---

## Overview

NKP (Nutanix Kubernetes Platform) management clusters include a set of **platform applications** that provide essential services for cluster operations, observability, security, and management. These applications are deployed via the **Kommander** component and managed through workspaces.

### Key Concepts

| Term | Description |
|------|-------------|
| **Platform Applications** | Pre-packaged applications deployed on management/workload clusters |
| **Workspace** | Logical grouping of clusters with shared configuration and apps |
| **Kommander** | NKP's multi-cluster management component |
| **Default Apps** | Applications installed automatically based on edition |
| **Optional Apps** | Applications that can be enabled/disabled per workspace |

---

## Platform Applications by Category

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    NKP PLATFORM APPLICATIONS                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐       │
│  │   OBSERVABILITY  │  │     SECURITY     │  │    NETWORKING    │       │
│  ├──────────────────┤  ├──────────────────┤  ├──────────────────┤       │
│  │ • Prometheus     │  │ • Gatekeeper     │  │ • Traefik        │       │
│  │ • Alertmanager   │  │ • Cert-Manager   │  │ • External-DNS   │       │
│  │ • Grafana        │  │ • Kube-OIDC-Proxy│  │ • MetalLB        │       │
│  │ • Loki           │  │ • Dex            │  │ • Istio (optional)│      │
│  │ • Fluent Bit     │  │ • Falco          │  │                  │       │
│  │ • Jaeger         │  │                  │  │                  │       │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘       │
│                                                                          │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐       │
│  │   MANAGEMENT     │  │     STORAGE      │  │    COST/AUDIT    │       │
│  ├──────────────────┤  ├──────────────────┤  ├──────────────────┤       │
│  │ • Kommander      │  │ • Nutanix CSI    │  │ • Kubecost       │       │
│  │ • Flux           │  │ • Velero         │  │ • Kubernetes     │       │
│  │ • Cluster API    │  │ • MinIO          │  │   Dashboard      │       │
│  │ • Kube State     │  │                  │  │ • Audit Logging  │       │
│  │   Metrics        │  │                  │  │                  │       │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Edition Availability Matrix

### Platform Application Availability by NKP Edition

| Application | Starter | Pro | Ultimate | Default in Pro/Ultimate |
|-------------|:-------:|:---:|:--------:|:-----------------------:|
| **Core/Essential** |
| Cert-Manager | ✓ | ✓ | ✓ | ✓ Default |
| Gatekeeper (OPA) | ✓ | ✓ | ✓ | ✓ Default |
| Traefik | ✓ | ✓ | ✓ | ✓ Default |
| Kubernetes Dashboard | ✓ | ✓ | ✓ | ✓ Default |
| Kube State Metrics | ✓ | ✓ | ✓ | ✓ Default |
| Node Exporter | ✓ | ✓ | ✓ | ✓ Default |
| **Observability** |
| Prometheus | Limited | ✓ | ✓ | ✓ Default |
| Alertmanager | Limited | ✓ | ✓ | ✓ Default |
| Grafana | - | ✓ | ✓ | Optional |
| Loki (Logging) | - | ✓ | ✓ | Optional |
| Fluent Bit | - | ✓ | ✓ | Optional |
| Jaeger (Tracing) | - | ✓ | ✓ | Optional |
| **Cost & Management** |
| Kubecost | - | ✓ | ✓ | ✓ Default (Ultimate) |
| Kommander (Fleet Mgmt) | - | Limited | ✓ | ✓ Default |
| Application Catalog | - | - | ✓ | ✓ Default |
| **Security** |
| Dex (SSO) | - | ✓ | ✓ | ✓ Default |
| Kube-OIDC-Proxy | - | ✓ | ✓ | ✓ Default |
| Falco | - | ✓ | ✓ | Optional |
| **Networking** |
| External-DNS | - | ✓ | ✓ | Optional |
| Istio Service Mesh | - | ✓ | ✓ | Optional |
| **Backup/Storage** |
| Velero | - | ✓ | ✓ | Optional |
| Nutanix CSI Driver | ✓ | ✓ | ✓ | ✓ Default |

---

## Core Platform Applications

### Cert-Manager

**Purpose:** Automated certificate management for Kubernetes

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes (all editions) |
| **Namespace** | `cert-manager` |
| **Min CPU** | 10m |
| **Min Memory** | 32 Mi |
| **Storage** | None (stateless) |
| **Replicas** | 1 (default), 3 (HA) |
| **Priority Class** | `system-cluster-critical` |

**Scaling Considerations:**
- Handles certificate issuance for all platform and user applications
- Scale replicas for HA in production
- Monitor certificate renewal queue depth

```yaml
# Resource limits for production
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

---

### Gatekeeper (OPA)

**Purpose:** Policy enforcement using Open Policy Agent

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes (all editions) |
| **Namespace** | `gatekeeper-system` |
| **Min CPU** | 300m |
| **Min Memory** | 768 Mi |
| **Storage** | None |
| **Replicas** | 3 (default for HA) |
| **Priority Class** | `system-cluster-critical` |

**Scaling Considerations:**
- CPU usage scales with number of admission requests
- Memory scales with number of policies and constraint templates
- Audit controller consumes additional resources

```yaml
# Production configuration
controller:
  replicas: 3
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 2Gi
audit:
  replicas: 1
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
```

---

### Traefik

**Purpose:** Ingress controller and load balancer

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes |
| **Namespace** | `kommander` |
| **Min CPU** | 100m |
| **Min Memory** | 128 Mi |
| **Storage** | None |
| **Replicas** | 2 (default) |

**Scaling Considerations:**
- Scale based on ingress traffic volume
- Consider dedicated nodes for high-traffic scenarios
- Use HPA for automatic scaling

```yaml
# HPA configuration for Traefik
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: traefik
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: traefik
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

---

### Kubernetes Dashboard

**Purpose:** Web UI for cluster management

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes |
| **Namespace** | `kubernetes-dashboard` |
| **Min CPU** | 100m |
| **Min Memory** | 200 Mi |
| **Storage** | None |
| **Replicas** | 1 |

---

## Observability Stack

### Prometheus Stack

The Prometheus stack is the core observability component, consisting of multiple sub-components:

#### Prometheus Server

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes (Pro/Ultimate) |
| **Namespace** | `kommander` |
| **Min CPU** | 1000m - 1500m |
| **Min Memory** | 4 - 8 Gi |
| **Storage (PV)** | 100 Gi (default) |
| **Replicas** | 2 (HA mode) |
| **Priority Class** | `dkp-high-priority` |

**Resource Scaling Formula:**

```
Memory (GB) ≈ (active_time_series × bytes_per_sample × retention_time_seconds) / (1024^3)

Typical: ~2-4 bytes per sample
Example: 1M time series × 4 bytes × 15 days × 86400 = ~5 GB
```

| Cluster Size | Time Series | Recommended Memory | Recommended Storage |
|--------------|-------------|-------------------|---------------------|
| Small (< 50 nodes) | ~500K | 4-8 GB | 50-100 GB |
| Medium (50-200 nodes) | ~2M | 8-16 GB | 100-250 GB |
| Large (200+ nodes) | ~5M+ | 16-32 GB | 250-500 GB |

#### Alertmanager

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes (with Prometheus) |
| **Namespace** | `kommander` |
| **Min CPU** | 100m |
| **Min Memory** | 256 Mi |
| **Storage** | 10 Gi |
| **Replicas** | 3 (HA) |

#### Node Exporter

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes |
| **Type** | DaemonSet (runs on every node) |
| **Min CPU per node** | 100m |
| **Min Memory per node** | 64 Mi |

#### Kube State Metrics

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes |
| **Min CPU** | 100m |
| **Min Memory** | 256 Mi |
| **Replicas** | 1-2 |

**Scaling:** Memory usage scales with number of Kubernetes objects (pods, services, deployments, etc.)

---

### Grafana

**Purpose:** Visualization and dashboarding

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Optional (Pro/Ultimate) |
| **Namespace** | `kommander` |
| **Min CPU** | 200m |
| **Min Memory** | 100 Mi |
| **Storage (PV)** | 10-32 Gi |
| **Replicas** | 1 (default), 2+ (HA) |
| **Priority Class** | `dkp-high-priority` |

**Scaling Considerations:**
- Memory scales with concurrent users and dashboard complexity
- Storage needed for dashboard persistence and plugins
- Consider read replicas for many users

```yaml
# Production Grafana configuration
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
persistence:
  enabled: true
  size: 20Gi
replicas: 2
```

---

### Loki (Logging Stack)

**Purpose:** Log aggregation and querying

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Optional |
| **Namespace** | `kommander` |
| **Architecture** | Distributed (ingester, querier, compactor) |
| **Default PVs** | 8 × 10 Gi = 80 Gi total |
| **Priority Class** | `dkp-high-priority` |

#### Loki Component Resources

| Component | Replicas | CPU | Memory | Storage |
|-----------|----------|-----|--------|---------|
| Ingester | 3 | 500m | 1 Gi | 10 Gi each |
| Querier | 2 | 500m | 1 Gi | - |
| Query Frontend | 2 | 200m | 256 Mi | - |
| Compactor | 1 | 500m | 1 Gi | 10 Gi |
| Distributor | 2 | 200m | 256 Mi | - |
| **Total (default)** | 10 | ~2.4 cores | ~4.5 Gi | 80 Gi |

**Scaling Guidelines:**

| Log Volume | Ingesters | Queriers | Total Storage |
|------------|-----------|----------|---------------|
| < 100 GB/day | 3 | 2 | 100-200 GB |
| 100-500 GB/day | 5 | 3 | 500 GB - 1 TB |
| > 500 GB/day | 10+ | 5+ | 1-5 TB |

---

### Fluent Bit

**Purpose:** Log collection and forwarding

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Optional |
| **Type** | DaemonSet |
| **Min CPU per node** | 350m |
| **Min Memory per node** | 350 Mi |

**Configuration for Scale:**

```yaml
# Fluent Bit resource configuration
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
# Buffer settings for high-volume logging
config:
  storage.total_limit_size: 5G
  storage.max_chunks_up: 128
```

---

### Jaeger (Tracing)

**Purpose:** Distributed tracing

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Optional |
| **Min CPU** | 500m |
| **Min Memory** | 512 Mi |
| **Storage** | 50-200 Gi |

---

## Security & Policy Applications

### Dex (Identity Provider)

**Purpose:** OIDC identity provider for SSO

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes (Pro/Ultimate) |
| **Namespace** | `kommander` |
| **Min CPU** | 100m |
| **Min Memory** | 128 Mi |
| **Replicas** | 2 (HA) |

---

### Kube-OIDC-Proxy

**Purpose:** OIDC authentication proxy for Kubernetes API

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes (Pro/Ultimate) |
| **Min CPU** | 100m |
| **Min Memory** | 128 Mi |

---

### Falco (Optional)

**Purpose:** Runtime security monitoring

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Optional |
| **Type** | DaemonSet |
| **Min CPU per node** | 200m |
| **Min Memory per node** | 512 Mi |

---

## Networking Applications

### External-DNS

**Purpose:** Automatic DNS record management

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Optional |
| **Min CPU** | 50m |
| **Min Memory** | 64 Mi |

---

### Istio Service Mesh (Optional)

**Purpose:** Service mesh for traffic management, security, observability

| Component | CPU | Memory | Notes |
|-----------|-----|--------|-------|
| Istiod | 500m | 2 Gi | Control plane |
| Istio Ingress | 100m per instance | 128 Mi | Data plane |
| Envoy Sidecar | 100m per pod | 128 Mi | Per application pod |

**Impact:** Adds ~10-15% CPU/memory overhead to workloads

---

## Storage & Data Services

### Velero (Backup)

**Purpose:** Cluster backup and disaster recovery

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Optional |
| **Min CPU** | 500m |
| **Min Memory** | 512 Mi |
| **Storage** | Requires object storage backend |

---

### Kubecost

**Purpose:** Cost monitoring and optimization

| Attribute | Value |
|-----------|-------|
| **Deployed By Default** | Yes (Ultimate), Optional (Pro) |
| **Namespace** | `kommander` |
| **Min CPU** | 700m - 1200m |
| **Min Memory** | 1.7 - 4 Gi |
| **Storage (PVs)** | 3 PVs: 2 Gi + 32 Gi + 32 Gi ≈ 66 Gi |
| **Priority Class** | `dkp-high-priority` |

**Scaling:**
- Memory scales with number of pods and namespaces tracked
- Storage scales with cost data retention period

---

## Resource Requirements Summary

### Total Platform Application Footprint

#### Minimal Deployment (Essential Apps Only)

| Resource | Amount |
|----------|--------|
| **Total CPU** | ~3-4 vCPU |
| **Total Memory** | ~8-12 GB |
| **Total Storage** | ~50-100 GB |

#### Standard Deployment (Pro Edition - Common Apps)

| Resource | Amount |
|----------|--------|
| **Total CPU** | ~8-12 vCPU |
| **Total Memory** | ~24-32 GB |
| **Total Storage** | ~200-300 GB |

#### Full Deployment (Ultimate Edition - All Apps)

| Resource | Amount |
|----------|--------|
| **Total CPU** | ~15-25 vCPU |
| **Total Memory** | ~48-64 GB |
| **Total Storage** | ~400-600 GB |

### Per-Application Quick Reference

| Application | CPU (Request) | Memory (Request) | Storage | Priority |
|-------------|---------------|------------------|---------|----------|
| Cert-Manager | 10m | 32 Mi | - | Critical |
| Gatekeeper | 300m | 768 Mi | - | Critical |
| Traefik | 100m | 128 Mi | - | High |
| Prometheus | 1000-1500m | 4-8 Gi | 100 Gi | High |
| Alertmanager | 100m | 256 Mi | 10 Gi | High |
| Grafana | 200m | 100-512 Mi | 10-32 Gi | High |
| Loki (total) | 2400m | 4.5 Gi | 80 Gi | High |
| Fluent Bit | 350m/node | 350 Mi/node | - | Medium |
| Kubecost | 700-1200m | 1.7-4 Gi | 66 Gi | High |
| Kube State Metrics | 100m | 256 Mi | - | Medium |
| Node Exporter | 100m/node | 64 Mi/node | - | Medium |
| Dex | 100m | 128 Mi | - | High |
| K8s Dashboard | 100m | 200 Mi | - | Low |

---

## Scaling Platform Applications

### Horizontal Scaling Strategies

#### 1. Prometheus Federation

For managing many clusters, use federation to reduce central Prometheus load:

```yaml
# Federation configuration
scrape_configs:
  - job_name: 'federate'
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job="prometheus"}'
        - '{__name__=~"job:.*"}'
    static_configs:
      - targets:
        - 'prometheus-cluster-1:9090'
        - 'prometheus-cluster-2:9090'
```

#### 2. Thanos for Long-Term Storage

Integrate Thanos for scalable long-term metrics storage:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Prometheus  │────▶│   Thanos    │────▶│   Object    │
│  (Cluster)  │     │   Sidecar   │     │   Storage   │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Thanos    │
                    │   Query     │◀──── Grafana
                    └─────────────┘
```

#### 3. Loki Scaling Modes

| Mode | Use Case | Configuration |
|------|----------|---------------|
| Monolithic | < 100 GB/day | Single binary |
| Simple Scalable | 100-500 GB/day | Read/Write separation |
| Microservices | > 500 GB/day | Full distributed |

#### 4. Remote Write for Metrics

Offload metrics to external systems:

```yaml
# Prometheus remote write configuration
remoteWrite:
  - url: "https://metrics-backend.example.com/write"
    queueConfig:
      maxSamplesPerSend: 10000
      capacity: 100000
```

---

### Vertical Scaling Guidelines

#### When to Scale Vertically

| Symptom | Application | Action |
|---------|-------------|--------|
| OOMKilled | Prometheus | Increase memory limit |
| High CPU throttling | Loki Ingester | Increase CPU limit |
| Slow queries | Grafana | Increase memory |
| Disk pressure | Prometheus | Increase PV size |

#### Recommended Limits by Scale

| Scale | Prometheus Memory | Loki Memory | Grafana Memory |
|-------|-------------------|-------------|----------------|
| Small | 8 GB | 4 GB | 512 MB |
| Medium | 16 GB | 8 GB | 1 GB |
| Large | 32 GB | 16 GB | 2 GB |
| X-Large | 64 GB | 32 GB | 4 GB |

---

## High Availability Configurations

### HA Replica Counts

| Application | Development | Production HA |
|-------------|-------------|---------------|
| Prometheus | 1 | 2 |
| Alertmanager | 1 | 3 |
| Grafana | 1 | 2+ |
| Loki Ingester | 1 | 3 |
| Loki Querier | 1 | 2 |
| Traefik | 1 | 2-3 |
| Cert-Manager | 1 | 3 |
| Gatekeeper | 1 | 3 |
| Dex | 1 | 2 |

### Pod Disruption Budgets

```yaml
# Example PDB for Prometheus
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: prometheus-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: prometheus
```

### Anti-Affinity Rules

```yaml
# Spread Alertmanager across nodes
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app.kubernetes.io/name: alertmanager
      topologyKey: kubernetes.io/hostname
```

---

## Tuning & Optimization

### Prometheus Optimization

```yaml
# Optimized Prometheus configuration
global:
  scrape_interval: 30s      # Increase for large clusters
  evaluation_interval: 30s
  
storage:
  tsdb:
    retention.time: 15d     # Reduce for less storage
    retention.size: 50GB    # Cap storage size
    
# Reduce cardinality
metric_relabel_configs:
  - source_labels: [__name__]
    regex: '(container_.*|kube_pod_container_.*)'
    action: drop
```

### Loki Optimization

```yaml
# Loki configuration for scale
limits_config:
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_streams_per_user: 10000
  max_chunks_per_query: 2000000

chunk_store_config:
  max_look_back_period: 168h  # 7 days

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h      # 30 days
```

### Grafana Optimization

```yaml
# Grafana performance settings
[server]
  concurrent_render_request_limit = 30

[database]
  max_idle_conn = 25
  max_open_conn = 100

[dataproxy]
  timeout = 60
  keep_alive_seconds = 30
```

### Resource Quotas for Platform Namespace

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: platform-apps-quota
  namespace: kommander
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 64Gi
    limits.cpu: "40"
    limits.memory: 128Gi
    persistentvolumeclaims: "20"
    requests.storage: 500Gi
```

---

## Troubleshooting Common Issues

### Issue: Prometheus OOMKilled

**Symptoms:** Prometheus pods restarting, OOMKilled events

**Solutions:**
1. Increase memory limits
2. Reduce scrape targets
3. Decrease retention period
4. Drop high-cardinality metrics

```bash
# Check memory usage
kubectl top pods -n kommander -l app=prometheus

# Check for high cardinality
curl -s localhost:9090/api/v1/status/tsdb | jq '.data.seriesCountByMetricName | to_entries | sort_by(-.value) | .[0:10]'
```

### Issue: Loki Ingestion Falling Behind

**Symptoms:** Log delay, ingester queue growing

**Solutions:**
1. Scale ingesters horizontally
2. Increase ingestion rate limits
3. Add more chunk storage
4. Reduce log verbosity at source

### Issue: Grafana Slow Dashboards

**Symptoms:** Dashboards take long to load, timeouts

**Solutions:**
1. Increase Grafana memory
2. Optimize queries (reduce time range, add filters)
3. Enable query caching
4. Use recording rules for expensive queries

### Issue: Certificate Renewal Failures

**Symptoms:** Expired certificates, cert-manager errors

**Solutions:**
1. Check cert-manager logs
2. Verify DNS/HTTP01 challenge accessibility
3. Check ClusterIssuer configuration
4. Ensure adequate permissions

```bash
# Debug cert-manager
kubectl describe certificate -A
kubectl logs -n cert-manager deploy/cert-manager -f
```

---

## Appendix: Platform App Deployment Checklist

### Pre-Deployment

- [ ] Verify storage class available for PVs
- [ ] Calculate total resource requirements
- [ ] Plan retention periods for metrics/logs
- [ ] Identify which optional apps to enable
- [ ] Configure external DNS (if using external-dns)
- [ ] Set up object storage for Velero/Thanos (if needed)

### Post-Deployment

- [ ] Verify all platform apps running
- [ ] Test Grafana dashboards loading
- [ ] Verify log collection in Loki
- [ ] Test alerting pipeline
- [ ] Configure backup schedules (Velero)
- [ ] Set up monitoring for platform apps themselves

### Scaling Checklist

- [ ] Monitor resource utilization trends
- [ ] Set up alerts for platform app health
- [ ] Plan PV expansion before hitting limits
- [ ] Document current vs projected capacity
- [ ] Test HA failover scenarios

---

## References

- NKP 2.17 Documentation: `/Users/deepak/Documents/NKP/Nutanix-Kubernetes-Platform-v2_17.pdf`
- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [Grafana Loki Documentation](https://grafana.com/docs/loki/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [OPA Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/)

---

*Document generated: January 2026*
*For the latest specifications, always refer to the official NKP documentation.*
