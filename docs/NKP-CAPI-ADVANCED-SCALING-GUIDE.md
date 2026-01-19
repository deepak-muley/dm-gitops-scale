# NKP + Cluster API Advanced Scaling Guide

This guide provides advanced scaling strategies, resource sizing, and actionable steps for scaling Cluster API (CAPI) with Nutanix Kubernetes Platform (NKP) management clusters.

> **Complements:** `CLUSTER-API-SCALING-DEEP-DIVE.md`, `CAPI-SCALING-SOLUTIONS-AND-FIXES.md`, `NKP-Sizing-Scale-Guide.md`
>
> **Last Updated:** January 2026

---

## Table of Contents

1. [Scale Tiers Overview](#scale-tiers-overview)
2. [Detailed Resource Sizing by Tier](#detailed-resource-sizing-by-tier)
3. [Additional Scaling Insights](#additional-scaling-insights)
4. [NKP-Specific Enhancements](#nkp-specific-enhancements)
5. [CAPX-Specific Tuning](#capx-specific-tuning)
6. [Advanced Architecture Patterns](#advanced-architecture-patterns)
7. [API Priority and Fairness Configuration](#api-priority-and-fairness-configuration)
8. [ClusterClass for Standardized Scale](#clusterclass-for-standardized-scale)
9. [Enhanced Monitoring and Alerts](#enhanced-monitoring-and-alerts)
10. [Actionable Steps by Scale Tier](#actionable-steps-by-scale-tier)
11. [Scale Testing Checklist](#scale-testing-checklist)
12. [References](#references)

---

## Scale Tiers Overview

| Tier | Clusters | Total Machines | Architecture Pattern | Key Challenge |
|------|----------|----------------|---------------------|---------------|
| **Small** | 1-20 | < 500 | Single NKP mgmt cluster | Baseline tuning |
| **Medium** | 20-100 | 500-2,500 | Single NKP, heavily tuned | Controller performance |
| **Large** | 100-500 | 2,500-10,000 | Namespace sharding OR multiple mgmt | etcd size, API server load |
| **XL** | 500-2,000 | 10,000-50,000 | Multiple mgmt clusters, regional | Coordination, observability |
| **Extreme** | 2,000+ | 50,000+ | Fleet controller + regional hubs | Full federation required |

---

## Detailed Resource Sizing by Tier

### Tier: Small (1-20 Clusters, < 500 Machines)

**Use Case:** Development, small production, POC environments

#### Management Cluster Resources

| Component | Nodes | vCPU/Node | RAM/Node | Storage/Node | Total Resources |
|-----------|-------|-----------|----------|--------------|-----------------|
| Control Plane + etcd | 3 | 4-6 | 16-24 GB | 100-150 GB SSD | 12-18 vCPU, 48-72 GB RAM |
| Workers (Observability) | 2-3 | 4-8 | 16-32 GB | 150-200 GB SSD | 8-24 vCPU, 32-96 GB RAM |
| **Total Management** | **5-6** | - | - | - | **20-42 vCPU, 80-168 GB RAM, 650-1050 GB** |

#### Controller Configuration

```yaml
# Small tier - minimal tuning needed
capi-controller-manager:
  kube-api-qps: 30
  kube-api-burst: 50
  cluster-concurrency: 20
  machine-concurrency: 20
  sync-period: 10m
  resources:
    requests: { cpu: "1", memory: "2Gi" }
    limits: { cpu: "2", memory: "4Gi" }
```

#### etcd Configuration

| Setting | Value |
|---------|-------|
| Storage Type | SSD |
| Disk IOPS | 1,000+ |
| quota-backend-bytes | 2 GB (default) |
| auto-compaction-retention | 1h |

---

### Tier: Medium (20-100 Clusters, 500-2,500 Machines)

**Use Case:** Mid-size production, multi-team environments

#### Management Cluster Resources

| Component | Nodes | vCPU/Node | RAM/Node | Storage/Node | Total Resources |
|-----------|-------|-----------|----------|--------------|-----------------|
| Control Plane + etcd | 3-5 | 8-12 | 32-48 GB | 200 GB NVMe | 24-60 vCPU, 96-240 GB RAM |
| Workers (Observability) | 3-5 | 12-16 | 32-64 GB | 300-500 GB SSD | 36-80 vCPU, 96-320 GB RAM |
| Workers (Controllers) | 2-3 | 8-12 | 16-32 GB | 150 GB SSD | 16-36 vCPU, 32-96 GB RAM |
| **Total Management** | **8-13** | - | - | - | **76-176 vCPU, 224-656 GB RAM, 1.8-3.5 TB** |

#### Controller Configuration

```yaml
# Medium tier - significant tuning
capi-controller-manager:
  kube-api-qps: 100
  kube-api-burst: 200
  cluster-concurrency: 50
  machine-concurrency: 100
  machinedeployment-concurrency: 50
  machineset-concurrency: 50
  sync-period: 20m
  resources:
    requests: { cpu: "4", memory: "8Gi" }
    limits: { cpu: "8", memory: "16Gi" }

kubeadm-control-plane-controller:
  kube-api-qps: 100
  kube-api-burst: 200
  kubeadmcontrolplane-concurrency: 50
  resources:
    requests: { cpu: "2", memory: "4Gi" }
    limits: { cpu: "4", memory: "8Gi" }

capx-controller-manager:
  kube-api-qps: 100
  kube-api-burst: 200
  nutanixcluster-concurrency: 30
  nutanixmachine-concurrency: 50
  resources:
    requests: { cpu: "2", memory: "4Gi" }
    limits: { cpu: "4", memory: "8Gi" }
```

#### etcd Configuration

| Setting | Value |
|---------|-------|
| Storage Type | NVMe SSD |
| Disk IOPS | 3,000+ |
| quota-backend-bytes | 4 GB |
| auto-compaction-retention | 30m |
| snapshot-count | 10000 |

#### API Server Configuration

```yaml
# API server tuning for medium tier
kube-apiserver:
  max-requests-inflight: 800      # Default: 400
  max-mutating-requests-inflight: 400  # Default: 200
  watch-cache-sizes:
    - resource: clusters.cluster.x-k8s.io, size: 500
    - resource: machines.cluster.x-k8s.io, size: 5000
```

---

### Tier: Large (100-500 Clusters, 2,500-10,000 Machines)

**Use Case:** Enterprise production, large organizations

#### Management Cluster Resources

| Component | Nodes | vCPU/Node | RAM/Node | Storage/Node | Total Resources |
|-----------|-------|-----------|----------|--------------|-----------------|
| Control Plane | 5 | 16 | 64 GB | 100 GB NVMe | 80 vCPU, 320 GB RAM |
| etcd (dedicated) | 5 | 8-16 | 32-64 GB | 300 GB NVMe | 40-80 vCPU, 160-320 GB RAM |
| Workers (Observability) | 5-8 | 16-24 | 64-96 GB | 500 GB-1 TB SSD | 80-192 vCPU, 320-768 GB RAM |
| Workers (Controllers) | 4-6 | 16 | 32-64 GB | 200 GB SSD | 64-96 vCPU, 128-384 GB RAM |
| **Total Management** | **19-24** | - | - | - | **264-448 vCPU, 928-1792 GB RAM, 5-9 TB** |

#### Architecture: Namespace Sharding

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    MANAGEMENT CLUSTER (Large Tier)                       │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │         Control Plane (5 nodes) + Dedicated etcd (5 nodes)        │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐            │
│  │ Namespace:     │  │ Namespace:     │  │ Namespace:     │            │
│  │ shard-a        │  │ shard-b        │  │ shard-c        │            │
│  │ Clusters 1-150 │  │ Clusters 151-300│ │ Clusters 301-500│           │
│  └───────┬────────┘  └───────┬────────┘  └───────┬────────┘            │
│          │                   │                   │                      │
│          ▼                   ▼                   ▼                      │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐            │
│  │ Controller     │  │ Controller     │  │ Controller     │            │
│  │ Instance A     │  │ Instance B     │  │ Instance C     │            │
│  │ --namespace=   │  │ --namespace=   │  │ --namespace=   │            │
│  │  shard-a       │  │  shard-b       │  │  shard-c       │            │
│  │ CPU: 8, Mem:16G│  │ CPU: 8, Mem:16G│  │ CPU: 8, Mem:16G│            │
│  └────────────────┘  └────────────────┘  └────────────────┘            │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Controller Configuration (Per Shard)

```yaml
# Large tier - sharded controllers
capi-controller-manager-shard-a:
  namespace: shard-a
  kube-api-qps: 100
  kube-api-burst: 200
  cluster-concurrency: 100
  machine-concurrency: 100
  sync-period: 30m
  leader-elect-resource-name: capi-controller-shard-a
  resources:
    requests: { cpu: "8", memory: "16Gi" }
    limits: { cpu: "16", memory: "32Gi" }
```

#### etcd Configuration (Dedicated Cluster)

| Setting | Value |
|---------|-------|
| Storage Type | NVMe RAID-1 |
| Disk IOPS | 5,000+ |
| Disk Latency | < 5ms p99 |
| quota-backend-bytes | 8 GB |
| auto-compaction-retention | 15m |
| snapshot-count | 5000 |
| heartbeat-interval | 100ms |
| election-timeout | 1000ms |

---

### Tier: XL (500-2,000 Clusters, 10,000-50,000 Machines)

**Use Case:** Large enterprise, multi-region deployments

#### Architecture: Multiple Regional Management Clusters

```
                        ┌─────────────────────────┐
                        │   Fleet Controller /    │
                        │   Central GitOps Repo   │
                        │   (ArgoCD / Flux)       │
                        │   8 vCPU, 16 GB RAM     │
                        └───────────┬─────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────────┐      ┌───────────────────┐      ┌───────────────────┐
│   Region: US-WEST │      │   Region: US-EAST │      │   Region: EU      │
│   ─────────────── │      │   ─────────────── │      │   ─────────────── │
│   NKP Management  │      │   NKP Management  │      │   NKP Management  │
│   Cluster         │      │   Cluster         │      │   Cluster         │
│   ~600 clusters   │      │   ~600 clusters   │      │   ~600 clusters   │
│   ~15K machines   │      │   ~15K machines   │      │   ~15K machines   │
└─────────┬─────────┘      └─────────┬─────────┘      └─────────┬─────────┘
          │                          │                          │
     Workload                   Workload                   Workload
     Clusters                   Clusters                   Clusters
```

#### Per-Regional Management Cluster Resources

| Component | Nodes | vCPU/Node | RAM/Node | Storage/Node | Total Resources |
|-----------|-------|-----------|----------|--------------|-----------------|
| Control Plane | 5 | 16-24 | 64-96 GB | 150 GB NVMe | 80-120 vCPU, 320-480 GB RAM |
| etcd (dedicated) | 5 | 16 | 64 GB | 500 GB NVMe | 80 vCPU, 320 GB RAM |
| Workers (Platform) | 8-12 | 24-32 | 96-128 GB | 500 GB-1 TB | 192-384 vCPU, 768-1536 GB RAM |
| **Per Regional Cluster** | **18-22** | - | - | - | **352-584 vCPU, 1.4-2.3 TB RAM, 8-15 TB** |
| **Total (3 Regions)** | **54-66** | - | - | - | **1056-1752 vCPU, 4.2-6.9 TB RAM, 24-45 TB** |

#### Fleet Controller Resources

| Component | Nodes | vCPU/Node | RAM/Node | Storage/Node |
|-----------|-------|-----------|----------|--------------|
| Fleet Control Plane | 3 | 8 | 32 GB | 200 GB SSD |
| Fleet Workers | 3 | 8-16 | 32-64 GB | 300 GB SSD |
| **Total Fleet Controller** | **6** | - | - | **48-72 vCPU, 192-288 GB RAM, 1.5 TB** |

#### Federated Observability Stack

| Component | Resources per Region | Total (3 Regions) |
|-----------|---------------------|-------------------|
| Prometheus | 8 vCPU, 32 GB, 2 TB | 24 vCPU, 96 GB, 6 TB |
| Thanos Sidecar | 2 vCPU, 4 GB | 6 vCPU, 12 GB |
| Thanos Query (central) | 8 vCPU, 16 GB | 8 vCPU, 16 GB |
| Thanos Store (central) | 4 vCPU, 16 GB, 500 GB | 4 vCPU, 16 GB, 500 GB |
| Object Storage (S3/Nutanix Objects) | - | 50-100 TB |

---

### Tier: Extreme (2,000+ Clusters, 50,000+ Machines)

**Use Case:** Hyperscale, service provider, massive multi-tenant

#### Architecture: Hierarchical Fleet with Karmada-Style Federation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          GLOBAL CONTROL PLANE                                │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ Karmada / Custom Federation Controller                                 │  │
│  │ - Policy distribution                                                  │  │
│  │ - Cross-cluster scheduling                                             │  │
│  │ - Global observability aggregation                                     │  │
│  │ Resources: 16 vCPU, 64 GB RAM per controller (HA: 3 instances)        │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
            ┌──────────────────────────┼──────────────────────────┐
            │                          │                          │
            ▼                          ▼                          ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   Regional Hub 1    │    │   Regional Hub 2    │    │   Regional Hub N    │
│   (Americas)        │    │   (EMEA)            │    │   (APAC)            │
│   ┌─────────────┐   │    │   ┌─────────────┐   │    │   ┌─────────────┐   │
│   │ NKP Mgmt 1  │   │    │   │ NKP Mgmt 1  │   │    │   │ NKP Mgmt 1  │   │
│   │ 500 clusters│   │    │   │ 500 clusters│   │    │   │ 500 clusters│   │
│   └─────────────┘   │    │   └─────────────┘   │    │   └─────────────┘   │
│   ┌─────────────┐   │    │   ┌─────────────┐   │    │   ┌─────────────┐   │
│   │ NKP Mgmt 2  │   │    │   │ NKP Mgmt 2  │   │    │   │ NKP Mgmt 2  │   │
│   │ 500 clusters│   │    │   │ 500 clusters│   │    │   │ 500 clusters│   │
│   └─────────────┘   │    │   └─────────────┘   │    │   └─────────────┘   │
│   ┌─────────────┐   │    │   ┌─────────────┐   │    │                     │
│   │ NKP Mgmt N  │   │    │   │ NKP Mgmt N  │   │    │                     │
│   │ 500 clusters│   │    │   │ 500 clusters│   │    │                     │
│   └─────────────┘   │    │   └─────────────┘   │    │                     │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

#### Resource Summary for Extreme Tier

| Layer | Component | Quantity | Per-Unit Resources | Total Resources |
|-------|-----------|----------|-------------------|-----------------|
| Global | Federation Controller | 3 (HA) | 16 vCPU, 64 GB, 200 GB | 48 vCPU, 192 GB, 600 GB |
| Global | Central Observability | 1 cluster | 96 vCPU, 384 GB, 10 TB | 96 vCPU, 384 GB, 10 TB |
| Regional | NKP Management Clusters | 10-20 | 352 vCPU, 1.4 TB, 8 TB each | 3,520-7,040 vCPU, 14-28 TB RAM, 80-160 TB |
| Regional | Regional Observability | 3-5 | 48 vCPU, 128 GB, 5 TB | 144-240 vCPU, 384-640 GB, 15-25 TB |
| **TOTAL** | - | - | - | **~4,000-7,500 vCPU, 15-30 TB RAM, 100-200 TB Storage** |

---

## Additional Scaling Insights

### Insights from CNCF Karmada (100 Large-Scale Clusters)

From [CNCF Blog: Support for 100 Large-Scale Clusters](https://www.cncf.io/blog/2022/11/29/support-for-100-large-scale-clusters/):

The Karmada project demonstrated managing **100 clusters × 5,000 nodes × 20,000 pods** (500K nodes, 2M+ pods total).

**Key Metrics to Track:**

| Metric | Target | Why It Matters |
|--------|--------|----------------|
| API call latency (mutating) | < 1s p99 | Critical for machine/cluster operations |
| API call latency (read-only) | < 1s p99 | LIST operations can be expensive |
| Resource distribution latency | < 2s p99 | Time to propagate changes across clusters |
| Cluster-to-controller heartbeat | < 5s | Health detection speed |

### Insights from PayPal (4K Nodes, 200K Pods)

From [PayPal: Scaling to 4K Nodes and 200K Pods](https://medium.com/paypal-tech/scaling-kubernetes-to-over-4k-nodes-and-200k-pods-29988fad6ed):

| Bottleneck | Solution |
|------------|----------|
| etcd slow transactions | Moved to NVMe SSDs, tuned compaction |
| API server LIST calls | Implemented pagination, reduced list frequency |
| Scheduler throughput | Tuned `--kube-api-qps` and `--kube-api-burst` to 400/800 |
| Controller manager watch count | Reduced informer resync periods |
| Network plugin (Calico) | Tuned BGP peer limits, used route reflectors |

**Scheduler Tuning for Large Clusters:**

```yaml
# Add to kube-scheduler for 1000+ node clusters
kube-scheduler:
  args:
  - --kube-api-qps=400
  - --kube-api-burst=800
  - --percentageOfNodesToScore=10  # Critical for 1000+ nodes
```

### CAPI In-Memory Provider for Scale Testing

For testing scale without real infrastructure:

```bash
# Install CAPI with in-memory provider
clusterctl init --infrastructure in-memory

# Create simulated clusters
cat <<EOF | kubectl apply -f -
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: test-cluster-001
  namespace: scale-test
spec:
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
    kind: InMemoryCluster
    name: test-cluster-001
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: test-cluster-001-cp
EOF
```

**Benefits:**
- Controllers actually reconcile (tests real controller performance)
- No infrastructure cost
- Can simulate machine failures, upgrades

---

## NKP-Specific Enhancements

### NKP 2.16.1+ Features Impacting Scale

| Feature | Scale Impact |
|---------|--------------|
| Kubernetes 1.33 support | Improved scheduler performance, better API server caching |
| Multi-infrastructure autoscaler fixes | Fixed failures when scaling across AHV + cloud |
| CIS-compliant hardened images | Reduced attack surface at scale |
| Proxy memory leak fixes | Critical for long-running management clusters |
| NKP Insights (Ultimate) | Fleet-wide observability and diagnostics |

### NKP Edition Considerations

| Edition | Recommended Max Clusters | Fleet Management | Insights |
|---------|-------------------------|------------------|----------|
| Starter | 1-5 | No | Basic |
| Pro | 20-50 | Yes | Yes |
| Ultimate | 50-100+ (per mgmt cluster) | Yes + Multi-cloud | Advanced |

### NKP Management Cluster Overhead by Edition

| Edition | Additional Overhead |
|---------|---------------------|
| Starter | Baseline |
| Pro | +20-30% (fleet management, advanced monitoring) |
| Ultimate | +40-50% (multi-cloud controllers, AI services, Insights) |

---

## CAPX-Specific Tuning

### CAPX Controller Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capx-controller-manager
  namespace: capx-system
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        # Standard tuning
        - --kube-api-qps=100
        - --kube-api-burst=200
        
        # CAPX-specific concurrency
        - --nutanixcluster-concurrency=50
        - --nutanixmachine-concurrency=100
        
        # Extended timeouts for slow VM operations
        - --vm-create-timeout=15m
        - --vm-delete-timeout=10m
        
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
          limits:
            cpu: "8"
            memory: "16Gi"
```

### Prism Central API Considerations

| Operation | Typical Latency | Rate Limit Recommendation |
|-----------|-----------------|--------------------------|
| VM Create | 30-120 seconds | Limit concurrent creates to ~10-20 |
| VM Delete | 10-30 seconds | Can be faster, batch up to 50 |
| VM List | 1-5 seconds | Cache results, reduce frequency |
| Volume Create | 5-30 seconds | Depends on storage tier |
| Image Clone | 10-60 seconds | Batch operations |

### Prism Central Sizing for Scale

| Scale Tier | Prism Central Size | Notes |
|------------|-------------------|-------|
| Small | Small (default) | Adequate for < 500 VMs |
| Medium | Large | Required for 500-2000 VMs |
| Large+ | X-Large or multiple PCs | Required for 2000+ VMs, consider PC federation |

---

## Advanced Architecture Patterns

### Pattern 1: Label-Based Controller Sharding

More flexible than namespace-only sharding:

```yaml
# Controller sharded by region label
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capi-controller-manager-shard-region-us
  namespace: capi-system
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        - --label-selector=cluster-region=us
        - --leader-elect=true
        - --leader-elect-resource-name=capi-controller-us
        - --kube-api-qps=100
        - --kube-api-burst=200
        - --cluster-concurrency=100
        resources:
          requests: { cpu: "8", memory: "16Gi" }
          limits: { cpu: "16", memory: "32Gi" }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capi-controller-manager-shard-region-eu
  namespace: capi-system
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        - --label-selector=cluster-region=eu
        - --leader-elect=true
        - --leader-elect-resource-name=capi-controller-eu
        - --kube-api-qps=100
        - --kube-api-burst=200
        - --cluster-concurrency=100
        resources:
          requests: { cpu: "8", memory: "16Gi" }
          limits: { cpu: "16", memory: "32Gi" }
```

**Cluster Labeling:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod-cluster-001
  labels:
    cluster-region: us          # Controller shard assignment
    cluster-tier: production    # For prioritization
    cluster-owner: team-a       # For RBAC/quota
```

### Pattern 2: Dedicated etcd Cluster

For Large tier and above:

```yaml
# External etcd cluster configuration
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
etcd:
  external:
    endpoints:
    - https://etcd-0.etcd.management.svc:2379
    - https://etcd-1.etcd.management.svc:2379
    - https://etcd-2.etcd.management.svc:2379
    - https://etcd-3.etcd.management.svc:2379
    - https://etcd-4.etcd.management.svc:2379
    caFile: /etc/kubernetes/pki/etcd/ca.crt
    certFile: /etc/kubernetes/pki/apiserver-etcd-client.crt
    keyFile: /etc/kubernetes/pki/apiserver-etcd-client.key
```

---

## API Priority and Fairness Configuration

Prevent cluster management operations from being throttled:

```yaml
# Priority level for CAPI operations
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: PriorityLevelConfiguration
metadata:
  name: cluster-api-priority
spec:
  type: Limited
  limited:
    nominalConcurrencyShares: 100
    lendablePercent: 0
    limitResponse:
      type: Queue
      queuing:
        queues: 64
        handSize: 6
        queueLengthLimit: 50
---
# Flow schema for CAPI controllers
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata:
  name: cluster-api-operations
spec:
  priorityLevelConfiguration:
    name: cluster-api-priority
  matchingPrecedence: 100
  rules:
  - subjects:
    - kind: ServiceAccount
      serviceAccount:
        name: capi-controller-manager
        namespace: capi-system
    - kind: ServiceAccount
      serviceAccount:
        name: capx-controller-manager
        namespace: capx-system
    - kind: ServiceAccount
      serviceAccount:
        name: capi-kubeadm-control-plane-controller-manager
        namespace: capi-kubeadm-control-plane-system
    resourceRules:
    - resources: ["clusters", "machines", "machinesets", "machinedeployments", "kubeadmcontrolplanes"]
      apiGroups: ["cluster.x-k8s.io", "controlplane.cluster.x-k8s.io"]
      verbs: ["*"]
```

---

## ClusterClass for Standardized Scale

Use ClusterClass (CAPI v1.5+) for consistent cluster creation at scale:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: ClusterClass
metadata:
  name: nkp-production-standard
  namespace: default
spec:
  controlPlane:
    ref:
      apiVersion: controlplane.cluster.x-k8s.io/v1beta1
      kind: KubeadmControlPlaneTemplate
      name: nkp-control-plane-template
    machineInfrastructure:
      ref:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: NutanixMachineTemplate
        name: nkp-control-plane-machine
  workers:
    machineDeployments:
    - class: default-worker
      template:
        bootstrap:
          ref:
            apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
            kind: KubeadmConfigTemplate
            name: nkp-worker-bootstrap
        infrastructure:
          ref:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
            kind: NutanixMachineTemplate
            name: nkp-worker-machine
    - class: gpu-worker
      template:
        bootstrap:
          ref:
            apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
            kind: KubeadmConfigTemplate
            name: nkp-gpu-worker-bootstrap
        infrastructure:
          ref:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
            kind: NutanixMachineTemplate
            name: nkp-gpu-worker-machine
  variables:
  - name: workerReplicas
    required: true
    schema:
      openAPIV3Schema:
        type: integer
        minimum: 1
        maximum: 100
        default: 3
  - name: controlPlaneReplicas
    required: false
    schema:
      openAPIV3Schema:
        type: integer
        enum: [1, 3, 5]
        default: 3
  - name: clusterRegion
    required: true
    schema:
      openAPIV3Schema:
        type: string
        enum: ["us-west", "us-east", "eu-west", "apac"]
```

**Using ClusterClass:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod-cluster-001
  namespace: production
spec:
  topology:
    class: nkp-production-standard
    version: v1.28.0
    controlPlane:
      replicas: 3
    workers:
      machineDeployments:
      - class: default-worker
        name: worker-pool
        replicas: 5
    variables:
    - name: workerReplicas
      value: 5
    - name: clusterRegion
      value: us-west
```

---

## Enhanced Monitoring and Alerts

### Additional Prometheus Alerts for Scale

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: capi-scale-alerts
spec:
  groups:
  - name: capi-scale
    rules:
    # Controller reconcile latency
    - alert: CAPIControllerHighReconcileLatency
      expr: histogram_quantile(0.99, sum(rate(controller_runtime_reconcile_time_seconds_bucket{controller=~"cluster|machine|kubeadmcontrolplane"}[5m])) by (controller, le)) > 60
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "CAPI controller {{ $labels.controller }} reconcile p99 > 60s"
        
    # Work queue backlog
    - alert: CAPIWorkQueueBacklog
      expr: workqueue_depth{name=~"cluster|machine"} > 100
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "CAPI {{ $labels.name }} queue depth > 100"
        
    # Machine provisioning stuck
    - alert: MachineProvisioningStuck
      expr: count(capi_machine_phase{phase="Provisioning"}) > 20
      for: 15m
      labels:
        severity: critical
      annotations:
        summary: "More than 20 machines stuck in Provisioning phase"
        
    # Cluster creation rate
    - alert: HighClusterCreationRate
      expr: sum(rate(capi_cluster_created_total[5m])) > 10
      for: 5m
      labels:
        severity: info
      annotations:
        summary: "High cluster creation rate: {{ $value }}/sec"
        
    # API server request latency
    - alert: APIServerHighLatency
      expr: histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m])) by (verb, le)) > 5
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "API server {{ $labels.verb }} p99 latency > 5s"

  - name: nutanix-scale
    rules:
    # Prism Central API latency (if metrics exposed)
    - alert: PrismCentralAPILatency
      expr: histogram_quantile(0.99, rate(nutanix_api_request_duration_seconds_bucket[5m])) > 5
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Prism Central API p99 latency > 5s"
        
    # VM creation failures
    - alert: NutanixVMCreationFailures
      expr: sum(rate(nutanix_vm_create_errors_total[5m])) > 0.1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Nutanix VM creation failures detected"
```

### Key PromQL Queries for Scale Monitoring

```promql
# Cluster count by phase
count(capi_cluster_phase) by (phase)

# Machine count by phase
count(capi_machine_phase) by (phase)

# Controller reconcile rate
sum(rate(controller_runtime_reconcile_total[5m])) by (controller)

# Controller reconcile errors
sum(rate(controller_runtime_reconcile_errors_total[5m])) by (controller)

# Work queue latency
histogram_quantile(0.99, sum(rate(workqueue_queue_duration_seconds_bucket[5m])) by (name, le))

# API server request rate
sum(rate(apiserver_request_total[5m])) by (verb, resource)

# etcd request latency
histogram_quantile(0.99, rate(etcd_request_duration_seconds_bucket[5m]))

# Controller memory usage trend
deriv(container_memory_working_set_bytes{namespace=~"capi.*"}[1h])
```

---

## Actionable Steps by Scale Tier

### Small Tier (1-20 Clusters) - Action Plan

#### Week 1: Baseline Setup

- [ ] **Deploy NKP management cluster** with 5-6 nodes (3 CP + 2-3 workers)
- [ ] **Install monitoring stack** (Prometheus, Grafana, Alertmanager)
- [ ] **Configure basic alerts** (etcd size, controller errors, API latency)
- [ ] **Document baseline metrics** for comparison

#### Week 2: Initial Tuning

- [ ] **Apply minimal controller patches:**
  ```bash
  kubectl -n capi-system patch deployment capi-controller-manager \
    --type=json -p='[
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-qps=30"},
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-burst=50"},
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--cluster-concurrency=20"}
    ]'
  ```
- [ ] **Test cluster creation** (create 5 clusters, measure times)
- [ ] **Validate observability** is capturing all required metrics

#### Week 3-4: Operational Readiness

- [ ] **Set up GitOps** for cluster definitions (Flux/ArgoCD)
- [ ] **Create ClusterClass templates** for standardization
- [ ] **Document runbooks** for common operations
- [ ] **Test DR procedures** (etcd backup/restore)

---

### Medium Tier (20-100 Clusters) - Action Plan

#### Phase 1: Infrastructure Preparation (Weeks 1-2)

- [ ] **Upgrade management cluster** to 8-13 nodes
  - 3-5 control plane nodes (8-12 vCPU, 32-48 GB RAM each)
  - 5-8 worker nodes (12-16 vCPU, 32-64 GB RAM each)
- [ ] **Upgrade storage to NVMe** for etcd nodes
- [ ] **Increase etcd quota:**
  ```yaml
  # Add to etcd static pod
  - --quota-backend-bytes=4294967296  # 4 GB
  - --auto-compaction-retention=30m
  ```
- [ ] **Validate Prism Central capacity** (upgrade to Large if needed)

#### Phase 2: Controller Tuning (Week 3)

- [ ] **Apply medium tier controller patches:**
  ```bash
  #!/bin/bash
  # patch-medium-tier.sh
  
  # CAPI Core
  kubectl -n capi-system patch deployment capi-controller-manager \
    --type=json -p='[
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-qps=100"},
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-burst=200"},
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--cluster-concurrency=50"},
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--machine-concurrency=100"},
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--sync-period=20m"}
    ]'
  
  # Increase resource limits
  kubectl -n capi-system patch deployment capi-controller-manager \
    --type=json -p='[
      {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "4"},
      {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "8Gi"},
      {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "8"},
      {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "16Gi"}
    ]'
  
  # Repeat for KCP and Bootstrap controllers...
  ```

- [ ] **Apply CAPX-specific tuning:**
  ```bash
  kubectl -n capx-system patch deployment capx-controller-manager \
    --type=json -p='[
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-qps=100"},
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-burst=200"},
      {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--nutanixmachine-concurrency=50"}
    ]'
  ```

#### Phase 3: Scale Testing (Weeks 4-5)

- [ ] **Create test clusters in batches:**
  ```bash
  # Create 10 clusters, wait for ready, repeat
  for batch in $(seq 1 10); do
    for i in $(seq 1 10); do
      kubectl apply -f cluster-$((($batch-1)*10+$i)).yaml &
    done
    wait
    echo "Waiting for batch $batch to stabilize..."
    sleep 300  # 5 minutes between batches
  done
  ```
- [ ] **Monitor during scale:**
  - etcd database size (< 3 GB target)
  - Controller reconcile times (< 30s p99)
  - API server latency (< 1s p99 for mutations)
  - Work queue depths (< 50)

- [ ] **Document scale test results**

#### Phase 4: Production Rollout (Weeks 6-8)

- [ ] **Migrate existing clusters** to new management cluster
- [ ] **Implement GitOps workflows** for all cluster definitions
- [ ] **Set up on-call alerting** with PagerDuty/Opsgenie
- [ ] **Create operational dashboards** for daily monitoring

---

### Large Tier (100-500 Clusters) - Action Plan

#### Phase 1: Architecture Decision (Week 1)

- [ ] **Decide sharding strategy:**
  - Option A: Namespace sharding (simpler, single cluster)
  - Option B: Multiple management clusters (more isolation)
- [ ] **Plan namespace/label scheme** for cluster assignment
- [ ] **Design network architecture** for management cluster HA

#### Phase 2: Infrastructure Build (Weeks 2-4)

- [ ] **Deploy dedicated etcd cluster** (5 nodes, 16 vCPU, 64 GB each)
  ```bash
  # etcd cluster with high performance settings
  etcd --quota-backend-bytes=8589934592 \
       --auto-compaction-mode=periodic \
       --auto-compaction-retention=15m \
       --snapshot-count=5000 \
       --heartbeat-interval=100 \
       --election-timeout=1000
  ```

- [ ] **Deploy management cluster** with dedicated etcd:
  - 5 control plane nodes (16 vCPU, 64 GB RAM)
  - 8-12 worker nodes (16-24 vCPU, 64-96 GB RAM)
  
- [ ] **Configure NVMe storage** with IOPS validation:
  ```bash
  # Test etcd disk performance
  fio --name=etcd-test --ioengine=libaio --direct=1 --rw=randrw \
      --bs=4k --numjobs=8 --runtime=60 --time_based --group_reporting \
      --filename=/var/lib/etcd/test.fio
  # Target: > 5000 IOPS, < 5ms latency
  ```

#### Phase 3: Controller Sharding (Weeks 5-6)

- [ ] **Deploy sharded controllers:**
  ```yaml
  # Create namespaces for shards
  kubectl create namespace shard-a
  kubectl create namespace shard-b
  kubectl create namespace shard-c
  
  # Deploy controller instances per shard
  # (use helm values or kustomize overlays)
  ```

- [ ] **Apply APF configuration** for prioritized API access

- [ ] **Test shard isolation:**
  ```bash
  # Verify controller A only reconciles shard-a
  kubectl logs -n capi-system deployment/capi-controller-shard-a | grep "Reconciling"
  ```

#### Phase 4: Scale Testing (Weeks 7-8)

- [ ] **Create clusters across shards:**
  ```bash
  # 150 clusters per shard
  for shard in shard-a shard-b shard-c; do
    for i in $(seq 1 150); do
      kubectl apply -f - <<EOF
  apiVersion: cluster.x-k8s.io/v1beta1
  kind: Cluster
  metadata:
    name: cluster-$i
    namespace: $shard
  spec:
    # ... cluster spec
  EOF
    done
  done
  ```

- [ ] **Measure per-shard performance:**
  ```promql
  # Reconcile time by controller shard
  histogram_quantile(0.99, sum(rate(controller_runtime_reconcile_time_seconds_bucket[5m])) by (controller, le))
  ```

#### Phase 5: Observability Scale (Weeks 9-10)

- [ ] **Deploy Thanos for federated metrics:**
  ```yaml
  # Thanos sidecar on Prometheus
  # Thanos Query for aggregated view
  # Object storage backend (Nutanix Objects)
  ```

- [ ] **Configure log aggregation** (Loki or EFK) with retention policies

- [ ] **Create fleet-wide dashboards:**
  - Cluster status overview
  - Resource utilization by shard
  - Top 10 slowest reconciliations

---

### XL Tier (500-2,000 Clusters) - Action Plan

#### Phase 1: Regional Architecture Design (Weeks 1-2)

- [ ] **Define regions** (e.g., us-west, us-east, eu-west, apac)
- [ ] **Plan IP addressing** for each region
- [ ] **Design inter-region connectivity** (VPN, dedicated links)
- [ ] **Select fleet controller** (ArgoCD ApplicationSets, Rancher Fleet, custom)

#### Phase 2: Fleet Controller Setup (Weeks 3-4)

- [ ] **Deploy central fleet controller cluster:**
  ```yaml
  # ArgoCD ApplicationSet for fleet
  apiVersion: argoproj.io/v1alpha1
  kind: ApplicationSet
  metadata:
    name: regional-management-clusters
  spec:
    generators:
    - list:
        elements:
        - region: us-west
          server: https://mgmt-uswest.example.com
        - region: us-east
          server: https://mgmt-useast.example.com
        - region: eu-west
          server: https://mgmt-euwest.example.com
    template:
      metadata:
        name: 'nkp-mgmt-{{region}}'
      spec:
        destination:
          server: '{{server}}'
          namespace: nkp-system
        source:
          repoURL: https://github.com/org/nkp-fleet
          path: 'regions/{{region}}'
  ```

- [ ] **Configure cross-cluster secrets management** (Vault, external-secrets)

#### Phase 3: Regional Management Clusters (Weeks 5-8)

- [ ] **Deploy management cluster per region** (Large tier sizing each)
- [ ] **Configure region-specific:**
  - Prism Central connections
  - Storage classes
  - Network configurations
  - Image registries

- [ ] **Test regional cluster creation** (50 clusters per region)

#### Phase 4: Federation and Observability (Weeks 9-12)

- [ ] **Deploy Thanos federation:**
  ```
  Region Prometheus → Thanos Sidecar → Object Storage
                                            ↓
                           Central Thanos Query ← Grafana
  ```

- [ ] **Configure global alerting** with region labels

- [ ] **Test failover scenarios:**
  - Regional management cluster failure
  - Fleet controller unavailability
  - Cross-region network partition

---

### Extreme Tier (2,000+ Clusters) - Action Plan

#### Phase 1: Federation Architecture (Months 1-2)

- [ ] **Evaluate federation options:**
  - Karmada
  - Open Cluster Management (OCM)
  - Custom federation controller

- [ ] **Design hierarchical control plane:**
  - Global control plane
  - Regional hubs (each managing 500-600 clusters)
  - NKP management clusters under each hub

- [ ] **Plan resource isolation:**
  - Blast radius limits
  - Failure domain separation
  - Upgrade wave strategies

#### Phase 2: Global Control Plane (Months 2-3)

- [ ] **Deploy global control plane cluster:**
  - 3-5 HA nodes for federation controller
  - Central policy engine
  - Global observability aggregation

- [ ] **Implement multi-level GitOps:**
  ```
  Global Repo
      ├── policies/           # Global policies
      ├── templates/          # ClusterClass definitions
      └── regions/
          ├── americas/
          │   ├── hub-config.yaml
          │   └── clusters/
          ├── emea/
          └── apac/
  ```

#### Phase 3: Regional Hubs (Months 3-6)

- [ ] **Deploy regional hub clusters** (3-5 hubs)
- [ ] **Deploy NKP management clusters** under each hub (2-4 per hub)
- [ ] **Configure hub-to-management cluster communication**
- [ ] **Test cross-hub operations**

#### Phase 4: Full Scale Testing (Months 6-8)

- [ ] **Gradual scale-up:**
  - Month 6: 500 clusters
  - Month 7: 1,000 clusters
  - Month 8: 2,000+ clusters

- [ ] **Measure and optimize:**
  - Resource distribution latency
  - Policy propagation time
  - Global reconciliation performance

---

## Scale Testing Checklist

### Pre-Scale: Infrastructure Validation

- [ ] Prism Central API response time < 2s
- [ ] Nutanix storage container IOPS > 5000 (Large+)
- [ ] Network switch backplane sufficient for cluster traffic
- [ ] IP pools have 3x expected machine count
- [ ] DNS server can handle cluster DNS queries
- [ ] NTP synchronized across all nodes

### Pre-Scale: Software Configuration

- [ ] Controller tuning applied for target tier
- [ ] etcd quota and compaction configured
- [ ] API server APF rules in place
- [ ] Monitoring and alerting operational
- [ ] Backup procedures tested

### During Scale: CAPI Monitoring

- [ ] Controller reconcile time < 60s p99
- [ ] Work queue depth < 100
- [ ] Controller CPU < 80% of limits
- [ ] Controller memory < 80% of limits
- [ ] No OOM kills

### During Scale: etcd Monitoring

- [ ] Database size < 75% of quota
- [ ] WAL fsync latency < 25ms p99
- [ ] Leader stable (no frequent elections)
- [ ] No alarms triggered

### During Scale: CAPX/Nutanix Monitoring

- [ ] Prism Central task queue depth stable
- [ ] No "RESOURCE_EXHAUSTED" errors
- [ ] VM creation time < 5 minutes p95
- [ ] AHV host CPU/memory utilization < 80%

### Post-Scale: Analysis

- [ ] Document maximum achieved scale
- [ ] Identify first bottleneck hit
- [ ] Record resource consumption curves
- [ ] Update sizing recommendations
- [ ] Plan next tier preparations

---

## References

### Nutanix & NKP

- [NKP 2.16.1 Release Notes](https://next.nutanix.com/product-updates/nutanix-kubernetes-platform-nkp-2-16-1-45030)
- [NKP Documentation](https://portal.nutanix.com/page/documents/details?targetId=Nutanix-Kubernetes-Platform-v2_17:Nutanix-Kubernetes-Platform-v2_17)
- [CAPX GitHub](https://github.com/nutanix-cloud-native/cluster-api-provider-nutanix)
- [Nutanix Bible - Cloud Native Services](https://www.nutanixbible.com/18a-book-of-cloud-native-services-nutanix-kubernetes-platform.html)

### Cluster API

- [Cluster API Book](https://cluster-api.sigs.k8s.io/)
- [CAPI Tuning Guide](https://cluster-api.sigs.k8s.io/developer/core/tuning)
- [CAPI Autoscaling](https://cluster-api.sigs.k8s.io/tasks/automated-machine-management/autoscaling)
- [CAPI In-Memory Provider](https://cluster-api.sigs.k8s.io/developer/providers/v1.7/in-memory-infrastructure)

### Kubernetes Scaling

- [Kubernetes Large Cluster Best Practices](https://kubernetes.io/docs/setup/best-practices/cluster-large/)
- [GKE Planning Large Clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/planning-large-clusters)
- [AKS Performance Scale Large](https://learn.microsoft.com/en-us/azure/aks/best-practices-performance-scale-large)

### Case Studies

- [CNCF: Support for 100 Large-Scale Clusters (Karmada)](https://www.cncf.io/blog/2022/11/29/support-for-100-large-scale-clusters/)
- [PayPal: Scaling to 4K Nodes and 200K Pods](https://medium.com/paypal-tech/scaling-kubernetes-to-over-4k-nodes-and-200k-pods-29988fad6ed)
- [Metal³ Scaling to 1000 Clusters](https://metal3.io/blog/2024/05/30/Scaling_part_3.html)
- [Spectro Cloud: 10K Clusters](https://www.spectrocloud.com/blog/how-we-tested-scaling-to-10-000-kubernetes-clusters-without-missing-a-beat)

### Tools

- [KWOK (Kubernetes Without Kubelet)](https://kwok.sigs.k8s.io/)
- [kube-burner](https://kube-burner.github.io/kube-burner/)
- [Karmada](https://karmada.io/)
- [Rancher Fleet](https://fleet.rancher.io/)

---

*Document generated: January 2026*
