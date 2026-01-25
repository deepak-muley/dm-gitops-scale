# Cluster API Scaling: Known Solutions, Fixes & Best Practices

This document provides **actionable solutions** and **proven fixes** for scaling Cluster API to thousands of clusters. It complements the deep-dive document with practical implementation guidance.

---

## Table of Contents

1. [Quick Reference: Known Fixes](#quick-reference-known-fixes)
2. [Controller Tuning Fixes](#controller-tuning-fixes)
3. [etcd Optimization](#etcd-optimization)
4. [Architecture Patterns for Scale](#architecture-patterns-for-scale)
5. [Cloud Provider Specific Solutions](#cloud-provider-specific-solutions)
6. [Monitoring Configuration](#monitoring-configuration)
7. [Resource Sizing Tables](#resource-sizing-tables)
8. [Top Resource Links](#top-resource-links)
9. [Implementation Checklist](#implementation-checklist)

---

## Quick Reference: Known Fixes

| Problem | Fix | Source |
|---------|-----|--------|
| Controllers hit rate limits at ~600 clusters | Increase `--kube-api-qps` to 100+, `--kube-api-burst` to 200+ | [Metal³ Scaling Part 3](https://metal3.io/blog/2024/05/30/Scaling_part_3.html) |
| Controller concurrency too low | Increase `--cluster-concurrency`, `--machine-concurrency` to 100+ | [Metal³ Scaling Part 3](https://metal3.io/blog/2024/05/30/Scaling_part_3.html) |
| KCP Controller high CPU (key generation) | Fixed in CAPI - keys are now cached/reused | [Metal³ Scaling Part 3](https://metal3.io/blog/2024/05/30/Scaling_part_3.html) |
| BMO endless requeues of deleted objects | Fixed in BMO v0.5+ | [Metal³ Scaling Part 3](https://metal3.io/blog/2024/05/30/Scaling_part_3.html) |
| Slow cluster creation (300 clusters = 135 min) | Namespace sharding of controllers | [CAPI Issue #8052](https://github.com/kubernetes-sigs/cluster-api/issues/8052) |
| etcd performance degradation | SSD/NVMe storage, regular compaction, increased quota | [etcd Hardware Guide](https://etcd.io/docs/v3.4/op-guide/hardware/) |
| API server overload | Increase replicas, tune APF, use watch/informers | [K8s Large Clusters](https://kubernetes.io/docs/setup/best-practices/cluster-large/) |

---

## Controller Tuning Fixes

### CAPI Core Controller Manager

```yaml
# Deployment patch for capi-controller-manager
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capi-controller-manager
  namespace: capi-system
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        # Rate limiting - CRITICAL for scale
        - --kube-api-qps=100        # Default: 20, increase for >500 clusters
        - --kube-api-burst=200      # Default: 30, increase for >500 clusters
        
        # Concurrency - how many objects reconciled in parallel
        - --cluster-concurrency=100          # Default: 10
        - --machine-concurrency=100          # Default: 10
        - --machinedeployment-concurrency=50 # Default: 10
        - --machineset-concurrency=50        # Default: 10
        - --machinehealthcheck-concurrency=50
        
        # Sync period - reduce periodic reconciliation load
        - --sync-period=30m          # Default: 10m, increase for large scale
        
        # Resource limits
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
          limits:
            cpu: "8"
            memory: "16Gi"
```

### Kubeadm Control Plane Controller

```yaml
# Deployment patch for capi-kubeadm-control-plane-controller-manager
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capi-kubeadm-control-plane-controller-manager
  namespace: capi-kubeadm-control-plane-system
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        - --kube-api-qps=100
        - --kube-api-burst=200
        - --kubeadmcontrolplane-concurrency=100  # Default: 10
        
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
          limits:
            cpu: "8"
            memory: "16Gi"
```

### Kubeadm Bootstrap Controller

```yaml
# Deployment patch for capi-kubeadm-bootstrap-controller-manager
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capi-kubeadm-bootstrap-controller-manager
  namespace: capi-kubeadm-bootstrap-system
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        - --kube-api-qps=100
        - --kube-api-burst=200
        - --kubeadmconfig-concurrency=100  # Default: 10
        - --cluster-concurrency=100
        
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
```

### Infrastructure Provider (Example: Nutanix CAPX)

```yaml
# For CAPX or other infrastructure providers
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
        # Common controller-runtime flags
        - --kube-api-qps=100
        - --kube-api-burst=200
        
        # Provider-specific concurrency (check provider docs)
        - --nutanixcluster-concurrency=50
        - --nutanixmachine-concurrency=100
        
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
          limits:
            cpu: "8"
            memory: "16Gi"
```

### One-Shot Patch Commands

```bash
#!/bin/bash
# patch-capi-for-scale.sh
# Apply scaling patches to all CAPI controllers

# CAPI Core
kubectl -n capi-system patch deployment capi-controller-manager \
  --type=json -p='[
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-qps=100"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-burst=200"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--cluster-concurrency=100"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--machine-concurrency=100"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--sync-period=30m"}
  ]'

# Kubeadm Control Plane
kubectl -n capi-kubeadm-control-plane-system patch deployment capi-kubeadm-control-plane-controller-manager \
  --type=json -p='[
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-qps=100"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-burst=200"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubeadmcontrolplane-concurrency=100"}
  ]'

# Kubeadm Bootstrap
kubectl -n capi-kubeadm-bootstrap-system patch deployment capi-kubeadm-bootstrap-controller-manager \
  --type=json -p='[
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-qps=100"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kube-api-burst=200"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubeadmconfig-concurrency=100"}
  ]'

echo "✓ All CAPI controllers patched for scale"
```

---

## etcd Optimization

### Hardware Requirements

| Scale | etcd Members | CPU per Member | Memory per Member | Storage | Disk Type |
|-------|--------------|----------------|-------------------|---------|-----------|
| < 500 clusters | 3 | 4 cores | 16 GB | 50 GB | SSD |
| 500-1,000 clusters | 3-5 | 8 cores | 32 GB | 100 GB | NVMe |
| 1,000-5,000 clusters | 5 | 16 cores | 64 GB | 200 GB | NVMe |
| 5,000+ clusters | Multiple etcd clusters | 32 cores | 128 GB | 500 GB | NVMe RAID |

### etcd Configuration

```yaml
# etcd configuration for high scale
# /etc/kubernetes/manifests/etcd.yaml additions

spec:
  containers:
  - name: etcd
    command:
    - etcd
    # Increase quota for large object counts
    - --quota-backend-bytes=8589934592   # 8 GB (default 2 GB)
    
    # Auto compaction
    - --auto-compaction-mode=periodic
    - --auto-compaction-retention=1h     # Compact every hour
    
    # Snapshot settings
    - --snapshot-count=10000             # More frequent snapshots
    
    # Performance tuning
    - --heartbeat-interval=100           # Default: 100ms
    - --election-timeout=1000            # Default: 1000ms
    
    # WAL settings (if supported)
    - --max-wals=5
    
    resources:
      requests:
        cpu: "8"
        memory: "32Gi"
      limits:
        cpu: "16"
        memory: "64Gi"
```

### etcd Maintenance Scripts

```bash
#!/bin/bash
# etcd-maintenance.sh
# Run weekly or when approaching limits

ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

echo "=== etcd Status ==="
kubectl exec -n kube-system $ETCD_POD -- etcdctl endpoint status --write-out=table

echo ""
echo "=== etcd Health ==="
kubectl exec -n kube-system $ETCD_POD -- etcdctl endpoint health

echo ""
echo "=== Database Size ==="
kubectl exec -n kube-system $ETCD_POD -- etcdctl endpoint status --write-out=json | jq '.[] | {endpoint: .Endpoint, dbSize: .Status.dbSize, dbSizeInUse: .Status.dbSizeInUse}'

echo ""
echo "=== Defragment (if needed) ==="
# Uncomment to defragment - WARNING: causes brief unavailability
# kubectl exec -n kube-system $ETCD_POD -- etcdctl defrag --cluster

echo ""
echo "=== Alarm List ==="
kubectl exec -n kube-system $ETCD_POD -- etcdctl alarm list
```

### etcd Alerts (Prometheus Rules)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: etcd-scale-alerts
spec:
  groups:
  - name: etcd-scale
    rules:
    # Database size approaching limit
    - alert: EtcdDatabaseSizeHigh
      expr: etcd_mvcc_db_total_size_in_bytes > 6442450944  # 6 GB
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "etcd database size high ({{ $value | humanize1024 }})"
        
    - alert: EtcdDatabaseSizeCritical
      expr: etcd_mvcc_db_total_size_in_bytes > 7516192768  # 7 GB
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "etcd database size critical ({{ $value | humanize1024 }})"
    
    # WAL fsync latency
    - alert: EtcdHighFsyncLatency
      expr: histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])) > 0.025
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "etcd WAL fsync p99 latency high ({{ $value }}s)"
    
    # Leader changes
    - alert: EtcdFrequentLeaderChanges
      expr: increase(etcd_server_leader_changes_seen_total[10m]) > 3
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: "etcd leader changed {{ $value }} times in 10 minutes"
    
    # Peer latency
    - alert: EtcdHighPeerLatency
      expr: histogram_quantile(0.99, rate(etcd_network_peer_round_trip_time_seconds_bucket[5m])) > 0.05
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "etcd peer p99 latency high ({{ $value }}s)"
```

---

## Architecture Patterns for Scale

### Pattern 1: Namespace Sharding (500-5,000 clusters)

Controllers watch only specific namespaces, reducing watch pressure.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Management Cluster                                │
├─────────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐           │
│  │ Namespace:    │  │ Namespace:    │  │ Namespace:    │           │
│  │ shard-a       │  │ shard-b       │  │ shard-c       │           │
│  │ Clusters 1-500│  │ Clusters 501+ │  │ Clusters 1001+│           │
│  └───────────────┘  └───────────────┘  └───────────────┘           │
│         │                  │                  │                     │
│         ▼                  ▼                  ▼                     │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐           │
│  │ Controller    │  │ Controller    │  │ Controller    │           │
│  │ Instance A    │  │ Instance B    │  │ Instance C    │           │
│  │ (watches      │  │ (watches      │  │ (watches      │           │
│  │  shard-a)     │  │  shard-b)     │  │  shard-c)     │           │
│  └───────────────┘  └───────────────┘  └───────────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```yaml
# Controller deployment with namespace selector
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capi-controller-manager-shard-a
  namespace: capi-system
spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        - --namespace=shard-a  # Only watch this namespace
        - --leader-elect=true
        - --leader-elect-resource-name=capi-controller-shard-a
```

### Pattern 2: Regional Management Clusters (5,000-15,000+ clusters)

Multiple independent management clusters, each handling a region or subset.

```
                    ┌─────────────────────────┐
                    │   Fleet Controller /    │
                    │   GitOps Repository     │
                    │   (Source of Truth)     │
                    └───────────┬─────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
│   Region: US-WEST │  │   Region: US-EAST │  │   Region: EU      │
│   ─────────────── │  │   ─────────────── │  │   ─────────────── │
│   Management      │  │   Management      │  │   Management      │
│   Cluster         │  │   Cluster         │  │   Cluster         │
│   ~5K clusters    │  │   ~5K clusters    │  │   ~5K clusters    │
│                   │  │                   │  │                   │
│   ┌──────────┐    │  │   ┌──────────┐    │  │   ┌──────────┐    │
│   │ CAPI     │    │  │   │ CAPI     │    │  │   │ CAPI     │    │
│   │ Stack    │    │  │   │ Stack    │    │  │   │ Stack    │    │
│   └──────────┘    │  │   └──────────┘    │  │   └──────────┘    │
└─────────┬─────────┘  └─────────┬─────────┘  └─────────┬─────────┘
          │                      │                      │
     Workload              Workload               Workload
     Clusters              Clusters               Clusters
```

**Tools for Fleet Management:**
- [Rancher Fleet](https://fleet.rancher.io/)
- [Red Hat ACM](https://www.redhat.com/en/technologies/management/advanced-cluster-management)
- [Argo CD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Cluster API ClusterResourceSets](https://cluster-api.sigs.k8s.io/tasks/experimental-features/cluster-resource-set)

### Pattern 3: Hierarchical Control Plane

```
┌─────────────────────────────────────────────────────────────────────┐
│                       Top-Level Control Plane                        │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ Fleet Controller                                               │  │
│  │ - Policy enforcement                                           │  │
│  │ - Cross-cluster observability                                  │  │
│  │ - Quota management                                             │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            │                       │                       │
            ▼                       ▼                       ▼
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Management Hub 1   │  │  Management Hub 2   │  │  Management Hub N   │
│  ─────────────────  │  │  ─────────────────  │  │  ─────────────────  │
│  CAPI + Provider    │  │  CAPI + Provider    │  │  CAPI + Provider    │
│  ~2,000 clusters    │  │  ~2,000 clusters    │  │  ~2,000 clusters    │
└──────────┬──────────┘  └──────────┬──────────┘  └──────────┬──────────┘
           │                        │                        │
    ┌──────┴──────┐          ┌──────┴──────┐          ┌──────┴──────┐
    ▼             ▼          ▼             ▼          ▼             ▼
 Workload     Workload    Workload     Workload    Workload     Workload
 Clusters     Clusters    Clusters     Clusters    Clusters     Clusters
```

---

## Cloud Provider Specific Solutions

### AWS EKS / CAPA Scaling

| Limit | Default | Increase Method |
|-------|---------|-----------------|
| Nodes per cluster | 100 (quota) | Request quota increase |
| vCPUs per region | Varies | Service Quotas console |
| ENIs per subnet | VPC dependent | Use prefix delegation |
| Security groups per ENI | 5 | Request increase |

**AWS Prefix Delegation (for IP exhaustion):**

```yaml
# Enable prefix delegation for more IPs per node
apiVersion: v1
kind: ConfigMap
metadata:
  name: amazon-vpc-cni
  namespace: kube-system
data:
  ENABLE_PREFIX_DELEGATION: "true"
  WARM_PREFIX_TARGET: "1"
```

**References:**
- [AWS EKS Scalability](https://docs.aws.amazon.com/eks/latest/best-practices/scalability.html)
- [EKS Ultra Scale (100K nodes)](https://aws.amazon.com/blogs/containers/under-the-hood-amazon-eks-ultra-scale-clusters/)

### GCP GKE / CAPG Scaling

| Limit | Default | Notes |
|-------|---------|-------|
| Nodes per cluster | 15,000 | Standard tier |
| Pods per cluster | 200,000 | Dependent on nodes |
| etcd database size | 6 GB | GKE managed |

**References:**
- [GKE Large Clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/planning-large-clusters)

### Azure AKS / CAPZ Scaling

| Limit | Default | Notes |
|-------|---------|-------|
| Nodes per cluster | 5,000 | Standard tier |
| Pods per cluster | 200,000 | With Azure CNI Overlay |

**References:**
- [AKS Performance Scale Large](https://learn.microsoft.com/en-us/azure/aks/best-practices-performance-scale-large)

### Nutanix CAPX Scaling Considerations

| Component | Consideration | Recommendation |
|-----------|---------------|----------------|
| Prism Central API | Rate limits | Check PC quotas, distribute requests |
| VM provisioning | Concurrent operations | Limit concurrent machine creates |
| Storage (Volumes) | IOPS limits | Ensure storage container capacity |
| Networking (AHV) | IP pool exhaustion | Plan IP ranges adequately |

**CAPX Controller Tuning:**

```yaml
# Based on CAPX controller flags
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
        - --leader-elect
        - --kube-api-qps=100
        - --kube-api-burst=200
        # Add provider-specific concurrency when available
```

**References:**
- [CAPX GitHub](https://github.com/nutanix-cloud-native/cluster-api-provider-nutanix)
- [CAPX Documentation](https://opendocs.nutanix.com/capx/latest/getting_started/)

---

## Monitoring Configuration

### Prometheus ServiceMonitors

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: capi-controllers
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames:
    - capi-system
    - capi-kubeadm-bootstrap-system
    - capi-kubeadm-control-plane-system
    - capx-system  # Nutanix provider
  selector:
    matchLabels:
      control-plane: controller-manager
  endpoints:
  - port: https
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
    interval: 30s
    path: /metrics
```

### Grafana Dashboard JSON (Key Panels)

```json
{
  "title": "Cluster API Scale Dashboard",
  "panels": [
    {
      "title": "Total Clusters",
      "type": "stat",
      "targets": [{
        "expr": "count(capi_cluster_info)"
      }]
    },
    {
      "title": "Total Machines",
      "type": "stat",
      "targets": [{
        "expr": "count(capi_machine_info)"
      }]
    },
    {
      "title": "Reconcile Duration by Controller",
      "type": "graph",
      "targets": [{
        "expr": "histogram_quantile(0.99, sum(rate(controller_runtime_reconcile_time_seconds_bucket[5m])) by (controller, le))",
        "legendFormat": "{{controller}}"
      }]
    },
    {
      "title": "Work Queue Depth",
      "type": "graph",
      "targets": [{
        "expr": "workqueue_depth{name=~\"cluster|machine|kubeadmcontrolplane\"}",
        "legendFormat": "{{name}}"
      }]
    },
    {
      "title": "Controller CPU Usage",
      "type": "graph",
      "targets": [{
        "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=~\"capi.*\"}[5m])) by (pod)",
        "legendFormat": "{{pod}}"
      }]
    },
    {
      "title": "Controller Memory Usage",
      "type": "graph",
      "targets": [{
        "expr": "sum(container_memory_working_set_bytes{namespace=~\"capi.*\"}) by (pod)",
        "legendFormat": "{{pod}}"
      }]
    },
    {
      "title": "etcd Database Size",
      "type": "graph",
      "targets": [{
        "expr": "etcd_mvcc_db_total_size_in_bytes",
        "legendFormat": "DB Size"
      }]
    },
    {
      "title": "API Server Request Latency (p99)",
      "type": "graph",
      "targets": [{
        "expr": "histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket{verb!=\"WATCH\"}[5m])) by (verb, le))",
        "legendFormat": "{{verb}}"
      }]
    }
  ]
}
```

### Key PromQL Queries for Scale Testing

```promql
# Controller performance
histogram_quantile(0.99, sum(rate(controller_runtime_reconcile_time_seconds_bucket[5m])) by (controller, le))

# Work queue backlog
sum(workqueue_depth) by (name)

# API server throttling (429s)
sum(rate(apiserver_request_total{code="429"}[5m])) by (resource)

# etcd operations latency
histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m]))

# Object counts
apiserver_storage_objects{resource=~"clusters|machines|machinesets"}

# Controller CPU saturation
sum(rate(container_cpu_usage_seconds_total{namespace=~"capi.*"}[5m])) by (pod) / 
sum(container_spec_cpu_quota{namespace=~"capi.*"}/container_spec_cpu_period{namespace=~"capi.*"}) by (pod)

# Memory pressure
container_memory_working_set_bytes{namespace=~"capi.*"} / container_spec_memory_limit_bytes{namespace=~"capi.*"}
```

---

## Resource Sizing Tables

### Management Cluster Control Plane

| Clusters | Machines | etcd Nodes | etcd CPU/Mem | API Server | Controllers CPU/Mem |
|----------|----------|------------|--------------|------------|---------------------|
| 100 | 1K | 3 | 4c/16G | 3 × 4c/16G | 2c/4G each |
| 500 | 5K | 3 | 8c/32G | 3 × 8c/32G | 4c/8G each |
| 1,000 | 10K | 5 | 16c/64G | 5 × 16c/32G | 8c/16G each |
| 5,000 | 50K | 5 | 32c/128G | 7 × 32c/64G | 16c/32G each |
| 10,000+ | 100K+ | Multiple clusters | - | Sharded | Sharded |

### Storage Performance Requirements

| Scale | etcd Disk | IOPS Required | Latency Target |
|-------|-----------|---------------|----------------|
| < 1K clusters | SSD | 1,000+ | < 10ms |
| 1K-5K clusters | NVMe | 5,000+ | < 5ms |
| 5K+ clusters | NVMe RAID | 10,000+ | < 2ms |

---

## Top Resource Links

### Official Documentation

| Resource | URL | Description |
|----------|-----|-------------|
| Cluster API Book | https://cluster-api.sigs.k8s.io/ | Official CAPI documentation |
| CAPI GitHub | https://github.com/kubernetes-sigs/cluster-api | Source code, issues |
| K8s Large Clusters | https://kubernetes.io/docs/setup/best-practices/cluster-large/ | Official limits |
| etcd Hardware Guide | https://etcd.io/docs/v3.4/op-guide/hardware/ | Hardware recommendations |

### Provider Repositories

| Provider | URL |
|----------|-----|
| Nutanix CAPX | https://github.com/nutanix-cloud-native/cluster-api-provider-nutanix |
| AWS CAPA | https://github.com/kubernetes-sigs/cluster-api-provider-aws |
| GCP CAPG | https://github.com/kubernetes-sigs/cluster-api-provider-gcp |
| Azure CAPZ | https://github.com/kubernetes-sigs/cluster-api-provider-azure |
| Metal³ CAPM3 | https://github.com/metal3-io/cluster-api-provider-metal3 |

### Scaling Case Studies

| Title | URL | Key Findings |
|-------|-----|--------------|
| Metal³ Scaling Part 3 | https://metal3.io/blog/2024/05/30/Scaling_part_3.html | 1000 clusters, controller tuning |
| Metal³ Scaling Part 2 | https://metal3.io/blog/2023/05/17/Scaling_part_2.html | Fake workload clusters |
| Metal³ Scaling Part 1 | https://metal3.io/blog/2023/05/10/Scaling_part_1.html | Test mode, BMH simulation |
| AWS EKS Ultra Scale | https://aws.amazon.com/blogs/containers/under-the-hood-amazon-eks-ultra-scale-clusters/ | 100K nodes |
| Spectro Cloud 10K Clusters | https://www.spectrocloud.com/blog/how-we-tested-scaling-to-10-000-kubernetes-clusters-without-missing-a-beat | 10K cluster management |
| EKS Scalability Testing | https://aws.amazon.com/blogs/containers/how-amazon-eks-approaches-scalability/ | 5K node testing |

### GitHub Issues for Scale

| Issue | Description |
|-------|-------------|
| [CAPI #8052](https://github.com/kubernetes-sigs/cluster-api/issues/8052) | Slow cluster creation with many clusters |
| [CAPI #5558](https://github.com/kubernetes-sigs/cluster-api/issues/5558) | Rate limit configuration |

---

## Implementation Checklist

### Phase 1: Baseline (< 100 clusters)

- [ ] Install CAPI with default settings
- [ ] Set up Prometheus/Grafana monitoring
- [ ] Establish baseline metrics for all controllers
- [ ] Test cluster create/delete cycle times

### Phase 2: Scale Preparation (100-500 clusters)

- [ ] Apply controller tuning patches (QPS, burst, concurrency)
- [ ] Upgrade etcd storage to SSD/NVMe
- [ ] Set up etcd alerts for size and latency
- [ ] Test with simulated clusters (KWOK, paused objects)

### Phase 3: Medium Scale (500-1,000 clusters)

- [ ] Increase controller resources (CPU/memory)
- [ ] Consider namespace sharding
- [ ] Implement etcd auto-compaction
- [ ] Review and increase sync-period if needed

### Phase 4: Large Scale (1,000-5,000 clusters)

- [ ] Implement namespace-based controller sharding
- [ ] Scale etcd cluster (5 members)
- [ ] Increase etcd quota-backend-bytes
- [ ] Consider multiple API server replicas

### Phase 5: Extreme Scale (5,000+ clusters)

- [ ] Deploy multiple management clusters
- [ ] Implement fleet/hierarchical control
- [ ] Set up federated monitoring (Thanos/Cortex)
- [ ] Plan regional distribution

### Ongoing Operations

- [ ] Weekly etcd health checks
- [ ] Monthly capacity review
- [ ] Quarterly scale testing
- [ ] Document any new bottlenecks discovered

---

## Quick Troubleshooting Guide

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Cluster creation slow (> 5 min) | Controller rate limited | Increase QPS/burst |
| Controllers high CPU | Low concurrency or expensive operations | Increase concurrency |
| etcd slow (fsync > 25ms) | Slow disk | Upgrade to NVMe |
| API server 429 errors | Rate limiting | Increase burst, reduce list frequency |
| Work queue backing up | Low concurrency | Increase controller concurrency |
| etcd database large (> 6GB) | Too many objects/events | Enable compaction, cleanup old objects |
| Controller OOM | Too many watched objects | Increase memory limits, consider sharding |
