# Cluster API Scaling Deep Dive: From 1,000 to 15,000 Clusters

This document provides a comprehensive analysis of scaling Cluster API (CAPI) and Kubernetes, drawing from the [Metal³ "Scaling to 1000 clusters" blog series](https://metal3.io/blog/2024/05/30/Scaling_part_3.html) and broader Kubernetes ecosystem knowledge.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Key Lessons from Metal³ Scaling to 1000 Clusters](#key-lessons-from-metal³-scaling-to-1000-clusters)
3. [Components in the Cluster API Ecosystem](#components-in-the-cluster-api-ecosystem)
4. [Metrics to Track with Prometheus & Grafana](#metrics-to-track-with-prometheus--grafana)
5. [Resource Footprints at Scale](#resource-footprints-at-scale)
6. [etcd Limits and Requirements](#etcd-limits-and-requirements)
7. [Kubernetes Control Plane Limits](#kubernetes-control-plane-limits)
8. [Scaling from 1,000 to 15,000 Clusters](#scaling-from-1000-to-15000-clusters)
9. [Component-by-Component Resource Requirements](#component-by-component-resource-requirements)
10. [Architecture Patterns for Extreme Scale](#architecture-patterns-for-extreme-scale)
11. [Observability Stack Scaling](#observability-stack-scaling)
12. [Checklist for Scale Testing](#checklist-for-scale-testing)
13. [Future: Nutanix NKP Integration Points](#future-nutanix-nkp-integration-points)

---

## Executive Summary

| Scale | Management Cluster Resources | Key Challenges | Architecture Pattern |
|-------|------------------------------|----------------|---------------------|
| **1-100 clusters** | Default settings work | Minimal | Single management cluster |
| **100-600 clusters** | Tune QPS/burst limits | Rate limiting begins | Single management cluster, tuned |
| **600-1,000 clusters** | High concurrency needed | Controller CPU, periodic sync overhead | Single management cluster, heavily tuned |
| **1,000-5,000 clusters** | Significant resources | etcd size, controller memory | Possibly sharded management |
| **5,000-15,000 clusters** | Massive resources | Single cluster won't suffice | Multiple management clusters, federated |

---

## Key Lessons from Metal³ Scaling to 1000 Clusters

The [Metal³ team's scaling experiments](https://metal3.io/blog/2024/05/30/Scaling_part_3.html) revealed critical bottlenecks:

### 1. Rate Limits Hit at ~600 Clusters

**Problem**: Default rate limits in client-go and controller-runtime are low:
- `client-go`: 10 QPS
- `controller-runtime`: 20 QPS

**Why 600 specifically?** 
- CAPI controllers reconcile every 10 minutes (600 seconds) by default
- At 600 clusters: 600 clusters ÷ 600 seconds = **1 API call/second** just for periodic sync
- Add event-driven reconciliations → immediate throttling

**Solution**: Patch controllers to increase limits:
```bash
kubectl -n capi-system patch deployment capi-controller-manager \
  --type=json -p='[
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-qps=100"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-burst=200"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--cluster-concurrency=100"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--machine-concurrency=100"}
  ]'
```

### 2. Controller Concurrency Too Low

**Problem**: Default concurrency is 10 (reconcile 10 objects in parallel)

**Impact**: At 1,000 clusters, reconciliation queue backs up

**Solution**: Increase concurrency per controller:
- `--cluster-concurrency=100`
- `--machine-concurrency=100`
- `--kubeadmcontrolplane-concurrency=100`
- `--kubeadmconfig-concurrency=100`

### 3. Kubeadm Control Plane Controller CPU Spikes

**Problem**: The controller was generating new private keys **4 times per reconciliation**

**Impact**: CPU usage dominated by cryptographic operations

**Solution**: Cache and reuse private keys (fixed in upstream CAPI)

### 4. Bare Metal Operator Log Spam

**Problem**: BMO endlessly requeued deleted objects

**Impact**: Unreadable logs, wasted CPU cycles

**Solution**: Bug fix to properly handle deleted objects

---

## Components in the Cluster API Ecosystem

Understanding what runs where is critical for sizing:

### Management Cluster Components

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MANAGEMENT CLUSTER                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Kubernetes Control Plane                             │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │ │
│  │  │ API Server  │  │    etcd     │  │  Scheduler  │  │ Controller  │   │ │
│  │  │             │  │  (3-5 nodes)│  │             │  │   Manager   │   │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Cluster API Controllers                              │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │ │
│  │  │  CAPI Core      │  │ Bootstrap       │  │ Control Plane   │        │ │
│  │  │  Controller     │  │ Provider        │  │ Provider        │        │ │
│  │  │  (Cluster,      │  │ (Kubeadm)       │  │ (Kubeadm)       │        │ │
│  │  │   Machine)      │  │                 │  │                 │        │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                Infrastructure Provider Controllers                      │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │ │
│  │  │ CAPM3 (Metal3)  │  │ CAPN (Nutanix)  │  │ CAPA/CAPZ/etc   │        │ │
│  │  │ + BMO           │  │                 │  │                 │        │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Supporting Services                                  │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │ │
│  │  │ Cert Manager    │  │ Ironic (Metal3) │  │ IPAM            │        │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Workload Cluster Components (per cluster)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         WORKLOAD CLUSTER (×N)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Control Plane (1-3 nodes)                           │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │ │
│  │  │ API Server  │  │    etcd     │  │  Scheduler  │  │ Controller  │   │ │
│  │  │             │  │             │  │             │  │   Manager   │   │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Worker Nodes (×M)                                   │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │ │
│  │  │ Kubelet         │  │ Kube-proxy      │  │ Container       │        │ │
│  │  │                 │  │                 │  │ Runtime         │        │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘        │ │
│  │  ┌─────────────────┐  ┌─────────────────┐                             │ │
│  │  │ CNI Plugin      │  │ CSI Driver      │                             │ │
│  │  └─────────────────┘  └─────────────────┘                             │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Objects Created per Cluster

| Object Type | Count per Cluster | At 1,000 Clusters | At 15,000 Clusters |
|-------------|-------------------|-------------------|---------------------|
| Cluster | 1 | 1,000 | 15,000 |
| Machine | N (nodes) | 1,000,000 (if 1000 nodes/cluster) | 15,000,000 |
| MachineSet | ~2-5 | 2,000-5,000 | 30,000-75,000 |
| MachineDeployment | ~2-5 | 2,000-5,000 | 30,000-75,000 |
| KubeadmControlPlane | 1 | 1,000 | 15,000 |
| KubeadmConfig | N | 1,000,000 | 15,000,000 |
| Secret (kubeconfig, certs) | ~10-20 | 10,000-20,000 | 150,000-300,000 |
| **Provider-specific** (Metal3Machine, NutanixMachine, etc.) | N | 1,000,000 | 15,000,000 |

---

## Metrics to Track with Prometheus & Grafana

### Tier 1: Critical Metrics (Alert Immediately)

#### etcd Health
```promql
# etcd database size (alert if approaching quota)
etcd_mvcc_db_total_size_in_bytes

# etcd leader changes (should be rare, alert if >3 in 10 minutes)
changes(etcd_server_leader_changes_seen_total[10m])

# etcd disk sync latency (alert if p99 > 25ms)
histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m]))

# etcd peer round trip time (alert if p99 > 50ms)
histogram_quantile(0.99, rate(etcd_network_peer_round_trip_time_seconds_bucket[5m]))

# etcd proposal failures
rate(etcd_server_proposals_failed_total[5m])
```

#### API Server Health
```promql
# API server request latency (alert if p99 > 1s for mutating)
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket{verb=~"POST|PUT|PATCH|DELETE"}[5m]))

# API server error rate
sum(rate(apiserver_request_total{code=~"5.."}[5m])) / sum(rate(apiserver_request_total[5m]))

# API server request queue length
apiserver_current_inflight_requests

# Watch count (indicates memory pressure)
apiserver_registered_watchers
```

#### Controller Health
```promql
# Reconcile duration by controller
histogram_quantile(0.99, rate(controller_runtime_reconcile_time_seconds_bucket[5m]))

# Reconcile errors
sum(rate(controller_runtime_reconcile_errors_total[5m])) by (controller)

# Work queue depth (backlog)
workqueue_depth{name=~".*"}

# Work queue latency (time items sit in queue)
histogram_quantile(0.99, rate(workqueue_queue_duration_seconds_bucket[5m]))
```

### Tier 2: Important Metrics (Monitor Trends)

#### Object Counts
```promql
# Total objects by type
apiserver_storage_objects{resource=~"clusters|machines|machinesets"}

# Object count growth rate
rate(apiserver_storage_objects[1h])
```

#### Controller Resources
```promql
# Controller CPU usage
sum(rate(container_cpu_usage_seconds_total{namespace=~"capi.*"}[5m])) by (pod)

# Controller memory usage
sum(container_memory_working_set_bytes{namespace=~"capi.*"}) by (pod)

# Controller restarts
sum(kube_pod_container_status_restarts_total{namespace=~"capi.*"}) by (pod)
```

#### Rate Limiting
```promql
# Client-side rate limiting (throttling)
rate(rest_client_requests_total{code="429"}[5m])

# API server admission latency
histogram_quantile(0.99, rate(apiserver_admission_controller_admission_duration_seconds_bucket[5m]))
```

### Tier 3: Workload Cluster Metrics

```promql
# Cluster readiness (requires aggregation from workload clusters)
# Track: nodes ready/total, control plane health, etcd health

# Per-cluster etcd size
etcd_mvcc_db_total_size_in_bytes{cluster="$cluster"}

# Per-cluster API server latency
apiserver_request_duration_seconds{cluster="$cluster"}

# Node registration time
# Custom metric: time from Machine creation to Node Ready
```

### Grafana Dashboard Structure

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Management Cluster Overview                               │
├──────────────────────┬──────────────────────┬──────────────────────────────┤
│  Cluster Count       │  Machine Count       │  Controller Health           │
│  ████████ 1,247      │  ████████ 1.2M       │  ✓ CAPI  ✓ CAPM3  ✓ BMO     │
├──────────────────────┴──────────────────────┴──────────────────────────────┤
│                           etcd Health                                       │
│  DB Size: 4.2GB / 8GB     Leader: stable     Peer Latency: 12ms p99        │
├─────────────────────────────────────────────────────────────────────────────┤
│                      Controller Performance                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Reconcile Duration (p99)                                            │   │
│  │ CAPI-core:     ████████░░ 450ms                                     │   │
│  │ CAPM3:         ██████████ 890ms                                     │   │
│  │ KCP:           ██████░░░░ 320ms                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────────────┤
│                      Work Queue Depth                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │         ^                                                           │   │
│  │   depth │    ╱╲                                                     │   │
│  │         │   ╱  ╲____                                                │   │
│  │         │__╱                                                        │   │
│  │         └──────────────────────────────────────────────> time       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Resource Footprints at Scale

### Management Cluster Sizing Guide

#### Scenario A: 1,000 Clusters × 10 Machines Each

| Component | CPU | Memory | Storage | Notes |
|-----------|-----|--------|---------|-------|
| **etcd (×3)** | 4-8 cores | 16-32 GB | 100 GB SSD | Low-latency NVMe preferred |
| **API Server (×3)** | 4-8 cores | 16-32 GB | - | May need HPA |
| **CAPI Controller** | 4 cores | 8 GB | - | Concurrency: 50+ |
| **KCP Controller** | 4 cores | 8 GB | - | After key-caching fix |
| **Bootstrap Controller** | 2 cores | 4 GB | - | Lower load |
| **Infrastructure Provider** | 4 cores | 8 GB | - | Depends on provider |
| **Total Management** | **40-60 cores** | **80-120 GB** | **300 GB+** | Across 3-5 nodes |

#### Scenario B: 1,000 Clusters × 1,000 Machines Each (1M Machines)

| Component | CPU | Memory | Storage | Notes |
|-----------|-----|--------|---------|-------|
| **etcd (×5)** | 16 cores | 64 GB | 500 GB NVMe | Must be fast |
| **API Server (×5)** | 16 cores | 64 GB | - | Heavy watch load |
| **CAPI Controller** | 16 cores | 32 GB | - | Concurrency: 100+ |
| **KCP Controller** | 8 cores | 16 GB | - | Per-cluster caching |
| **Bootstrap Controller** | 8 cores | 16 GB | - | 1M KubeadmConfigs |
| **Infrastructure Provider** | 16 cores | 32 GB | - | 1M provider objects |
| **Total Management** | **200+ cores** | **400+ GB** | **2 TB+** | 10-20 nodes |

#### Scenario C: 15,000 Clusters × 1,000 Machines Each (15M Machines)

**⚠️ SINGLE MANAGEMENT CLUSTER NOT RECOMMENDED**

This scale requires architectural changes:

| Architecture Option | Description |
|---------------------|-------------|
| **Federated Management** | Multiple management clusters, each handling ~1,000-2,000 workload clusters |
| **Hierarchical** | Central "super-management" cluster managing regional management clusters |
| **Sharded** | Partition clusters by namespace, label, or hash into separate etcd clusters |

Estimated total resources (distributed across multiple management clusters):

| Resource | Estimate | Notes |
|----------|----------|-------|
| **Total CPU** | 3,000+ cores | Across all management clusters |
| **Total Memory** | 6+ TB | Primarily for controllers and etcd |
| **Total Storage** | 30+ TB | etcd, logs, metrics |
| **Network** | 40 Gbps+ | Between components |

### Workload Cluster Sizing (Per Cluster)

| Nodes per Cluster | Control Plane CPU | Control Plane Memory | etcd Storage |
|-------------------|-------------------|----------------------|--------------|
| 10-50 | 2 cores × 3 | 4 GB × 3 | 10 GB |
| 50-200 | 4 cores × 3 | 8 GB × 3 | 20 GB |
| 200-500 | 8 cores × 3 | 16 GB × 3 | 50 GB |
| 500-1,000 | 16 cores × 3 | 32 GB × 3 | 100 GB |
| 1,000-5,000 | 32 cores × 3+ | 64 GB × 3+ | 200 GB+ |

---

## etcd Limits and Requirements

### Hard Limits

| Limit | Default Value | Maximum Recommended | Notes |
|-------|---------------|---------------------|-------|
| **Database size** | 2 GB quota | 8 GB | Configurable via `--quota-backend-bytes` |
| **Object size** | 1.5 MB | 1.5 MB | Hard limit per object |
| **Request size** | 1.5 MB | 1.5 MB | Per request |
| **Watch connections** | No hard limit | ~10,000 | Memory scales with watchers |
| **Keys** | No hard limit | Millions | Performance degrades |
| **Cluster members** | No hard limit | 5-7 | Consensus overhead increases |

### Hardware Requirements by Scale

| Scale | CPU per etcd | Memory per etcd | Disk | Disk Type | Network |
|-------|--------------|-----------------|------|-----------|---------|
| **Small** (<100 nodes) | 2 cores | 8 GB | 20 GB | SSD | 1 Gbps |
| **Medium** (100-500 nodes) | 4 cores | 16 GB | 50 GB | SSD | 10 Gbps |
| **Large** (500-1,000 nodes) | 8 cores | 32 GB | 100 GB | NVMe | 10 Gbps |
| **Very Large** (1,000-5,000 nodes) | 16 cores | 64 GB | 200 GB | NVMe | 25 Gbps |
| **Extreme** (5,000+ nodes) | 32 cores | 128 GB | 500 GB | NVMe RAID | 40 Gbps |

### Critical Disk Requirements

```
ETCD DISK LATENCY REQUIREMENTS
─────────────────────────────────
│ WAL fsync p99 │ Health Status │
├───────────────┼───────────────┤
│     < 10ms    │   Healthy     │
│   10ms - 25ms │   Warning     │
│   25ms - 50ms │   Degraded    │
│     > 50ms    │   Critical    │
└───────────────┴───────────────┘
```

### etcd Maintenance Operations

```bash
# Check etcd database size
etcdctl endpoint status --write-out=table

# Compact etcd (removes old revisions)
ETCD_REVISION=$(etcdctl endpoint status --write-out=json | jq -r '.header.revision')
etcdctl compact $ETCD_REVISION

# Defragment etcd (reclaims disk space)
etcdctl defrag --cluster

# Check alarm status
etcdctl alarm list

# Clear alarms after fixing issues
etcdctl alarm disarm
```

---

## Kubernetes Control Plane Limits

### Official Limits (as of v1.31)

| Resource | Limit | Notes |
|----------|-------|-------|
| **Nodes per cluster** | 5,000 | Tested and supported |
| **Pods per node** | 110 | Default, configurable |
| **Total pods per cluster** | 150,000 | Soft limit |
| **Total containers per cluster** | 300,000 | Soft limit |
| **Pods per namespace** | No limit | Practical: ~10,000 |
| **Services per cluster** | 10,000 | Endpoint slice helps |
| **Endpoints per service** | 1,000 | EndpointSlice: unlimited |
| **ConfigMaps/Secrets** | No limit | etcd storage bound |

### API Server Scaling

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| **Request latency (p99)** | < 1s (mutating), < 200ms (read-only) | > 2s |
| **In-flight requests** | < 400 mutating, < 200 read-only | > 80% |
| **Watch count** | Scales with controllers | > 10,000 per API server |
| **QPS** | Depends on hardware | Throttling errors |

---

## Scaling from 1,000 to 15,000 Clusters

### What Changes

| Aspect | At 1,000 Clusters | At 15,000 Clusters | Multiplier |
|--------|-------------------|---------------------|------------|
| **Cluster objects** | 1,000 | 15,000 | 15× |
| **Machine objects** | 10K - 1M | 150K - 15M | 15× |
| **etcd writes/sec** | ~100-500 | ~1,500-7,500 | 15× |
| **Controller memory** | 8-32 GB | 120-480 GB | 15× |
| **Watch connections** | ~1,000 | ~15,000 | 15× |
| **Reconcile queue depth** | Manageable | Likely backed up | - |
| **API server load** | Medium | Extreme | 15× |

### Bottlenecks That Emerge

```
SCALING BOTTLENECK PROGRESSION
──────────────────────────────────────────────────────────────────────────────
Clusters │ Primary Bottleneck        │ Secondary Bottleneck
─────────┼───────────────────────────┼──────────────────────────────────────
    100  │ Usually none              │ -
    500  │ Controller QPS limits     │ -
  1,000  │ Controller concurrency    │ Controller CPU (key generation)
  2,500  │ etcd write throughput     │ Controller memory
  5,000  │ etcd database size        │ API server in-flight requests
 10,000  │ Single etcd cluster limit │ Network bandwidth
 15,000  │ Single management cluster │ Everything
──────────────────────────────────────────────────────────────────────────────
```

### Required Changes for 15,000 Clusters

#### 1. Multiple Management Clusters

```
                         ┌─────────────────────┐
                         │   Global Control    │
                         │   (Orchestration)   │
                         └──────────┬──────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            │                       │                       │
            ▼                       ▼                       ▼
   ┌────────────────┐     ┌────────────────┐     ┌────────────────┐
   │   Management   │     │   Management   │     │   Management   │
   │   Cluster 1    │     │   Cluster 2    │     │   Cluster N    │
   │  (5K clusters) │     │  (5K clusters) │     │  (5K clusters) │
   └────────────────┘     └────────────────┘     └────────────────┘
          │                       │                       │
    ┌─────┴─────┐           ┌─────┴─────┐           ┌─────┴─────┐
    ▼           ▼           ▼           ▼           ▼           ▼
 Workload   Workload    Workload   Workload    Workload   Workload
 Clusters   Clusters    Clusters   Clusters    Clusters   Clusters
```

#### 2. Controller Tuning (per management cluster)

```yaml
# Example: Aggressive tuning for high scale
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capi-controller-manager
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        - --kube-api-qps=500
        - --kube-api-burst=1000
        - --cluster-concurrency=200
        - --machine-concurrency=500
        - --sync-period=30m  # Reduce periodic sync frequency
        resources:
          requests:
            cpu: "8"
            memory: "32Gi"
          limits:
            cpu: "16"
            memory: "64Gi"
```

#### 3. etcd Separation

```
ETCD SEPARATION STRATEGIES
──────────────────────────────────────────────────────────────────────────────

Option A: Separate etcd for events
┌─────────────┐     ┌─────────────┐
│ Main etcd   │     │ Events etcd │
│ (core data) │     │ (high churn)│
└─────────────┘     └─────────────┘

Option B: External etcd per management cluster
┌─────────────────────────────────────────────────┐
│ Management Cluster K8s (etcd-less control plane)│
└─────────────────────┬───────────────────────────┘
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
   ┌─────────────┐         ┌─────────────┐
   │ External    │         │ External    │
   │ etcd Pool 1 │         │ etcd Pool 2 │
   └─────────────┘         └─────────────┘
```

---

## Component-by-Component Resource Requirements

### CAPI Core Controller Manager

| Clusters | CPU | Memory | Key Settings |
|----------|-----|--------|--------------|
| 100 | 0.5 cores | 512 MB | Defaults OK |
| 500 | 2 cores | 2 GB | Raise concurrency |
| 1,000 | 4 cores | 8 GB | QPS: 50+, Concurrency: 50+ |
| 5,000 | 16 cores | 32 GB | QPS: 200+, Concurrency: 200+ |

### Kubeadm Control Plane Controller

| Clusters | CPU | Memory | Notes |
|----------|-----|--------|-------|
| 100 | 0.5 cores | 512 MB | |
| 500 | 2 cores | 2 GB | After key-caching fix |
| 1,000 | 4 cores | 8 GB | |
| 5,000 | 8 cores | 16 GB | Certificate operations add up |

### Kubeadm Bootstrap Controller

| Clusters × Machines | CPU | Memory | Notes |
|---------------------|-----|--------|-------|
| 100 × 10 | 0.5 cores | 512 MB | |
| 1,000 × 100 | 2 cores | 4 GB | |
| 1,000 × 1,000 | 8 cores | 16 GB | 1M KubeadmConfig objects |

### Infrastructure Provider (e.g., CAPM3, CAPN)

| Machines | CPU | Memory | Notes |
|----------|-----|--------|-------|
| 1,000 | 1 core | 1 GB | |
| 10,000 | 4 cores | 8 GB | |
| 100,000 | 8 cores | 16 GB | |
| 1,000,000 | 32 cores | 64 GB | May need sharding |

### Bare Metal Operator (Metal3)

| BareMetalHosts | CPU | Memory | Notes |
|----------------|-----|--------|-------|
| 100 | 0.5 cores | 512 MB | |
| 1,000 | 2 cores | 4 GB | |
| 10,000 | 8 cores | 16 GB | Ironic scaling needed too |

---

## Architecture Patterns for Extreme Scale

### Pattern 1: Regional Management Clusters

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          GLOBAL LAYER                                       │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │ GitOps Repository (Source of Truth)                                 │   │
│  │ - Cluster definitions                                               │   │
│  │ - Policy & configuration                                            │   │
│  │ - Fleet-wide settings                                               │   │
│  └────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐           ┌───────────────┐           ┌───────────────┐
│  REGION: US   │           │ REGION: EMEA  │           │ REGION: APAC  │
│ ────────────  │           │ ────────────  │           │ ────────────  │
│ Management    │           │ Management    │           │ Management    │
│ Cluster       │           │ Cluster       │           │ Cluster       │
│ ~5K clusters  │           │ ~5K clusters  │           │ ~5K clusters  │
└───────┬───────┘           └───────┬───────┘           └───────┬───────┘
        │                           │                           │
   Workload                    Workload                    Workload
   Clusters                    Clusters                    Clusters
```

### Pattern 2: Namespace-Sharded Management

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SINGLE LARGE MANAGEMENT CLUSTER                          │
│                    (with namespace-based sharding)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │ Namespace:      │  │ Namespace:      │  │ Namespace:      │             │
│  │ shard-001       │  │ shard-002       │  │ shard-NNN       │             │
│  │ ─────────────── │  │ ─────────────── │  │ ─────────────── │             │
│  │ Clusters: 1-500 │  │ Clusters: 501+  │  │ Clusters: N+    │             │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘             │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Controller Sharding (leader election per namespace)                  │   │
│  │ Each controller instance owns specific namespaces                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Pattern 3: Hierarchical Control Planes

```
                    ┌─────────────────────────┐
                    │    Fleet Controller     │
                    │   (Rancher Fleet,       │
                    │    Argo Fleet, etc.)    │
                    └───────────┬─────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
│   Hub Cluster 1   │  │   Hub Cluster 2   │  │   Hub Cluster N   │
│   (Management)    │  │   (Management)    │  │   (Management)    │
│   ┌───────────┐   │  │   ┌───────────┐   │  │   ┌───────────┐   │
│   │  CAPI     │   │  │   │  CAPI     │   │  │   │  CAPI     │   │
│   │  Stack    │   │  │   │  Stack    │   │  │   │  Stack    │   │
│   └───────────┘   │  │   └───────────┘   │  │   └───────────┘   │
└─────────┬─────────┘  └─────────┬─────────┘  └─────────┬─────────┘
          │                      │                      │
     Spoke Clusters         Spoke Clusters         Spoke Clusters
     (Workloads)            (Workloads)            (Workloads)
```

---

## Observability Stack Scaling

### Prometheus Architecture at Scale

```
                              ┌─────────────────────────┐
                              │    Grafana Dashboard    │
                              │    (Query Federation)   │
                              └───────────┬─────────────┘
                                          │
                   ┌──────────────────────┼──────────────────────┐
                   │                      │                      │
                   ▼                      ▼                      ▼
          ┌───────────────┐      ┌───────────────┐      ┌───────────────┐
          │  Thanos Query │      │  Thanos Store │      │ Thanos Compact│
          └───────┬───────┘      └───────┬───────┘      └───────────────┘
                  │                      │
      ┌───────────┴───────────┐          │
      │                       │          │
      ▼                       ▼          ▼
┌───────────┐           ┌───────────┐  ┌─────────────┐
│Prometheus │           │Prometheus │  │Object Store │
│  Shard 1  │           │  Shard N  │  │ (S3/GCS)    │
│ (Mgmt)    │           │(Workload) │  └─────────────┘
└───────────┘           └───────────┘
```

### Metrics Storage Sizing

| Scale | Metrics/sec | Daily Storage | 30-day Retention |
|-------|-------------|---------------|------------------|
| 100 clusters | ~50K | ~5 GB | 150 GB |
| 1,000 clusters | ~500K | ~50 GB | 1.5 TB |
| 15,000 clusters | ~7.5M | ~750 GB | 22.5 TB |

### Cardinality Management

**High Cardinality Labels to Avoid:**
- Per-cluster unique IDs as labels
- Per-pod/container unique names
- Timestamps in label values
- User IDs, request IDs

**Recommended Label Strategy:**
```yaml
# Good: Limited cardinality
labels:
  cluster_type: "workload"
  region: "us-west-2"
  environment: "production"
  provider: "metal3"

# Bad: Explosive cardinality
labels:
  cluster_id: "cluster-abc123-unique-id"  # Unique per cluster
  machine_id: "machine-xyz789"             # Unique per machine
```

---

## Checklist for Scale Testing

### Pre-Scale Checklist

- [ ] **Baseline measurements** at small scale (10-50 clusters)
  - [ ] etcd database size
  - [ ] Controller CPU/memory
  - [ ] API server latency
  - [ ] Reconcile duration

- [ ] **Controller configuration**
  - [ ] Increase `--kube-api-qps` (recommend: 100+)
  - [ ] Increase `--kube-api-burst` (recommend: 200+)
  - [ ] Increase concurrency flags (recommend: 100+)
  - [ ] Consider increasing `--sync-period` (reduce periodic reconciliation)

- [ ] **etcd preparation**
  - [ ] Fast SSD/NVMe storage
  - [ ] Network latency < 10ms between peers
  - [ ] Quota increased if needed (`--quota-backend-bytes`)
  - [ ] Auto-compaction enabled

- [ ] **Monitoring setup**
  - [ ] Prometheus scraping all components
  - [ ] Alerts configured for critical metrics
  - [ ] Grafana dashboards ready

### During Scale Test

- [ ] **Monitor continuously**
  - [ ] etcd leader stability
  - [ ] etcd disk latency
  - [ ] Controller queue depth
  - [ ] API server latency
  - [ ] Memory usage trends

- [ ] **Watch for**
  - [ ] Rate limiting errors (429s)
  - [ ] Controller restarts
  - [ ] etcd alarms
  - [ ] OOM kills

### Post-Scale Analysis

- [ ] **Identify bottlenecks**
  - [ ] Which component saturated first?
  - [ ] What was the limiting factor?
  - [ ] Where did latency spike?

- [ ] **Document findings**
  - [ ] Resource consumption curves
  - [ ] Breaking points
  - [ ] Configuration that worked

---

## Future: Nutanix NKP Integration Points

When expanding to include Nutanix NKP, consider these additional components and metrics:

### Additional Components

| Component | Role | Scaling Consideration |
|-----------|------|----------------------|
| **CAPX (Nutanix Provider)** | Creates Nutanix VMs | Similar to other providers |
| **Nutanix CSI Driver** | Storage provisioning | Per-cluster overhead |
| **Karbon** | NKP cluster management | May have own limits |
| **Prism Central** | API endpoint | Rate limits, connection limits |

### Additional Metrics to Track

```promql
# Nutanix API latency
nutanix_api_request_duration_seconds

# VM provisioning time
nutanix_vm_create_duration_seconds

# Storage provisioning latency
nutanix_volume_create_duration_seconds

# Prism Central connection health
nutanix_prism_connection_status
```

### Nutanix-Specific Limits

| Resource | Typical Limit | Notes |
|----------|---------------|-------|
| VMs per cluster (Nutanix) | 25,000 | AHV limit |
| API calls to Prism | Rate limited | Check documentation |
| Concurrent VM operations | ~50-100 | Provider configurable |

---

## References

- [Metal³ "Scaling to 1000 clusters - Part 3"](https://metal3.io/blog/2024/05/30/Scaling_part_3.html)
- [Metal³ "Scaling to 1000 clusters - Part 2"](https://metal3.io/blog/2023/05/17/Scaling_part_2.html)
- [Metal³ "Scaling to 1000 clusters - Part 1"](https://metal3.io/blog/2023/05/10/Scaling_part_1.html)
- [etcd Hardware Recommendations](https://etcd.io/docs/v3.5/op-guide/hardware/)
- [Kubernetes Large Cluster Best Practices](https://kubernetes.io/docs/setup/best-practices/cluster-large/)
- [GKE Planning Large Clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/planning-large-clusters)
- [CAPI In-Memory Provider](https://cluster-api.sigs.k8s.io/developer/providers/v1.7/in-memory-infrastructure)
- [OKD etcd Performance](https://docs.okd.io/latest/scalability_and_performance/recommended-performance-scale-practices/recommended-etcd-practices.html)
