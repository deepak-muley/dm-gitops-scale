# Scaling Kubernetes Management Clusters: Actionable Guide

> **Purpose:** Comprehensive, actionable guide for scaling the number of Kubernetes clusters managed by a management cluster with Cluster API and platform applications.
>
> **Last Updated:** January 2026

---

## Table of Contents

1. [Overview](#overview)
2. [Terminology](#terminology)
3. [Actionable Items for Scaling](#actionable-items-for-scaling)
4. [Resource Requests and Limits](#resource-requests-and-limits)
5. [Resource Quotas and Limit Ranges](#resource-quotas-and-limit-ranges)
6. [Bin Packing on Management Clusters](#bin-packing-on-management-clusters)
7. [Platform Pod Scheduling Strategies](#platform-pod-scheduling-strategies)
8. [CAPI QPS and Performance Tuning](#capi-qps-and-performance-tuning)
9. [Resource Utilization Monitoring](#resource-utilization-monitoring)
10. [Additional Scaling Strategies](#additional-scaling-strategies)
11. [Observability Stack Scaling (Prometheus, Loki, Logging Operator, etcd)](#observability-stack-scaling-prometheus-loki-logging-operator-etcd)
    1. [Thanos: Comprehensive Scaling Guide](#thanos-comprehensive-scaling-guide)
    2. [Thanos Deployment Strategies by Tier](#thanos-deployment-strategies-by-tier)
    3. [Thanos Memory Optimization](#thanos-memory-optimization)
    4. [Thanos Tier-Specific Configurations](#thanos-tier-specific-configurations)
    5. [Thanos Object Storage Options](#thanos-object-storage-options)
    6. [Thanos Monitoring & Alerts](#thanos-monitoring--alerts)
    7. [Thanos Implementation Checklist](#thanos-implementation-checklist)
12. [Implementation Checklist](#implementation-checklist)
13. [References](#references)

---

## Overview

Scaling a Kubernetes management cluster to handle hundreds or thousands of workload clusters requires careful planning, configuration, and monitoring. This guide provides actionable steps organized by priority and scale tier.

### Scale Tiers

| Tier | Clusters | Machines | Management Cluster Size | Key Focus |
|------|----------|----------|-------------------------|-----------|
| **XS** | 1-10 | < 100 | Small (3-5 nodes) | Baseline configuration |
| **S** | 10-50 | 100-500 | Medium (5-8 nodes) | Resource limits, basic tuning |
| **M** | 50-200 | 500-2,000 | Large (8-15 nodes) | Bin packing, advanced tuning |
| **L** | 200-1,000 | 2,000-10,000 | XL (15-30 nodes) | Sharding, dedicated resources |
| **XL+** | 1,000+ | 10,000+ | Multiple clusters | Federation, hierarchical |

---

## Terminology

### Core Kubernetes Concepts

#### **Resource Requests and Limits**
- **Request**: The minimum amount of CPU/memory guaranteed to a pod. Kubernetes uses this for scheduling decisions.
- **Limit**: The maximum amount of CPU/memory a pod can consume. If exceeded, the pod may be throttled (CPU) or killed (memory).
- **Why it matters**: Without requests/limits, pods can consume unbounded resources, leading to node exhaustion and scheduling failures.

#### **Resource Quotas**
- **Definition**: A namespace-level constraint that limits the total resource consumption (CPU, memory, storage, object counts) across all pods in a namespace.
- **Purpose**: Prevents a single namespace from consuming all cluster resources.
- **Example**: Limit `capi-system` namespace to 100 CPU cores and 200 GB memory total.

#### **Limit Ranges**
- **Definition**: A namespace-level constraint that sets default, minimum, and maximum values for resource requests/limits per pod or container.
- **Purpose**: Enforces resource policies automatically when pods are created without explicit requests/limits.
- **Example**: Automatically set 100m CPU request and 128Mi memory request for all pods in a namespace.

#### **Bin Packing**
- **Definition**: A scheduling strategy that maximizes resource utilization by concentrating pods on fewer nodes rather than spreading them evenly.
- **How it works**: The scheduler scores nodes based on current resource allocation, favoring nodes with higher utilization.
- **Use case**: Reduces infrastructure costs by maximizing node utilization, ideal for management clusters where you want to minimize node count.

#### **Anti-Affinity**
- **Definition**: A pod scheduling rule that prevents pods from being scheduled on the same node (or zone) as other pods.
- **Types**:
  - **Pod Anti-Affinity**: Prevents pods from co-locating with specific other pods.
  - **Node Anti-Affinity**: Prevents pods from being scheduled on specific nodes.
- **Use case**: Distribute platform services across nodes for high availability.

#### **Pod Affinity**
- **Definition**: A pod scheduling rule that encourages pods to be scheduled on the same node (or zone) as other pods.
- **Use case**: Co-locate related services for performance (e.g., database and application).

#### **Kube Scheduler**
- **Definition**: The Kubernetes component responsible for assigning pods to nodes based on resource availability, constraints, and policies.
- **Scoring plugins**: Determine which node is best for a pod (e.g., `NodeResourcesFit`, `NodeAffinity`).
- **Filtering plugins**: Eliminate nodes that cannot run the pod (e.g., insufficient resources, taints).

#### **QPS (Queries Per Second)**
- **Definition**: The rate at which a client (e.g., controller) can make API requests to the Kubernetes API server.
- **Burst**: The maximum number of requests that can be sent in a short burst, even if it exceeds QPS.
- **Why it matters**: Controllers hitting rate limits will be throttled, slowing down reconciliation and cluster operations.

#### **Reconciliation**
- **Definition**: The process by which a controller compares the desired state (from Kubernetes objects) with the actual state and makes changes to align them.
- **Reconcile loop**: The continuous cycle of checking and updating resources.
- **Reconcile duration**: Time taken for one reconciliation cycle.

#### **Controller Concurrency**
- **Definition**: The number of objects a controller reconciles in parallel.
- **Default**: Usually 10 concurrent reconciliations.
- **Impact**: Higher concurrency allows faster processing but increases CPU/memory usage and API server load.

#### **etcd**
- **Definition**: The distributed key-value store that stores all Kubernetes cluster data (pods, services, configs, etc.).
- **Quota**: Maximum database size (default 2 GB, can be increased to 8 GB).
- **Compaction**: Process of removing old revisions to free space.
- **Why it matters**: etcd performance is critical for cluster operations; slow etcd = slow cluster.

#### **Node Pool**
- **Definition**: A group of nodes with similar characteristics (CPU, memory, storage, labels, taints).
- **Use case**: Dedicate specific node pools for specific workloads (e.g., platform services, user workloads).

#### **Taints and Tolerations**
- **Taint**: A property of a node that repels pods unless they have a matching toleration.
- **Toleration**: A property of a pod that allows it to be scheduled on a tainted node.
- **Use case**: Reserve nodes for specific workloads (e.g., only platform pods can run on platform nodes).

---

## Actionable Items for Scaling

### Priority 1: Foundation (All Tiers)

#### 1. Set Requests and Limits for All Resources

**Why**: Without resource requests/limits, pods can consume unbounded resources, leading to:
- Node exhaustion
- Scheduling failures
- OOM (Out of Memory) kills
- CPU throttling

**Action Items**:

```yaml
# Example: CAPI Controller with proper resource requests/limits
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
        resources:
          requests:
            cpu: "500m"      # Minimum guaranteed CPU
            memory: "512Mi"  # Minimum guaranteed memory
          limits:
            cpu: "2000m"     # Maximum CPU (can be throttled)
            memory: "2Gi"    # Maximum memory (OOM if exceeded)
```

**Apply to**:
- All CAPI controllers (CAPI core, KCP, Bootstrap, Infrastructure providers)
- Platform applications (Prometheus, Grafana, Alertmanager, etc.)
- System components (kube-proxy, CNI plugins, CSI drivers)

**Commands**:
```bash
# Patch existing deployments
kubectl -n capi-system patch deployment capi-controller-manager \
  --type=json -p='[
    {"op": "add", "path": "/spec/template/spec/containers/0/resources", 
     "value": {
       "requests": {"cpu": "500m", "memory": "512Mi"},
       "limits": {"cpu": "2000m", "memory": "2Gi"}
     }}
  ]'

# Verify resource usage
kubectl top pods -n capi-system
```

#### 2. Use Resource Quotas and Limit Ranges

**Why**: Prevents resource exhaustion and enforces resource policies automatically.

**Action Items**:

**Create Resource Quotas by Namespace**:

```yaml
# Resource quota for capi-system namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: capi-resource-quota
  namespace: capi-system
spec:
  hard:
    requests.cpu: "50"           # Total CPU requests
    requests.memory: "100Gi"      # Total memory requests
    limits.cpu: "100"             # Total CPU limits
    limits.memory: "200Gi"        # Total memory limits
    pods: "100"                   # Maximum pods
    persistentvolumeclaims: "10"  # Maximum PVCs
    services: "20"               # Maximum services
```

**Create Limit Ranges**:

```yaml
# Limit range for automatic resource assignment
apiVersion: v1
kind: LimitRange
metadata:
  name: capi-limit-range
  namespace: capi-system
spec:
  limits:
  - default:                    # Default limits if not specified
      cpu: "1000m"
      memory: "1Gi"
    defaultRequest:              # Default requests if not specified
      cpu: "100m"
      memory: "128Mi"
    max:                        # Maximum allowed
      cpu: "4000m"
      memory: "4Gi"
    min:                        # Minimum required
      cpu: "50m"
      memory: "64Mi"
    type: Container
```

**Tier-Specific Quotas**:

| Tier | CPU Request | Memory Request | CPU Limit | Memory Limit | Pods |
|------|-------------|----------------|-----------|--------------|------|
| **XS** | 10 cores | 20 Gi | 20 cores | 40 Gi | 50 |
| **S** | 50 cores | 100 Gi | 100 cores | 200 Gi | 200 |
| **M** | 200 cores | 400 Gi | 400 cores | 800 Gi | 500 |
| **L** | 500 cores | 1 Ti | 1,000 cores | 2 Ti | 1,000 |

**Commands**:
```bash
# Apply resource quota
kubectl apply -f resource-quota.yaml

# Check quota usage
kubectl describe resourcequota -n capi-system

# Check limit range
kubectl describe limitrange -n capi-system
```

#### 3. Perform Bin Packing on Management Clusters

**Why**: Maximizes resource utilization, reduces infrastructure costs, and allows more workload clusters to be managed with fewer management cluster nodes.

**Action Items**:

**Configure Scheduler with Bin Packing**:

```yaml
# KubeSchedulerConfiguration for bin packing
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
  plugins:
    score:
      disabled:
      - name: NodeResourcesFit
        weight: 0
      enabled:
      - name: NodeResourcesFit
        weight: 1
  pluginConfig:
  - name: NodeResourcesFit
    args:
      scoringStrategy:
        type: MostAllocated  # Use bin packing strategy
        resources:
        - name: cpu
          weight: 1
        - name: memory
          weight: 1
```

**Apply Configuration**:

```bash
# Create ConfigMap
kubectl create configmap scheduler-config \
  --from-file=config.yaml=scheduler-config.yaml \
  -n kube-system

# Update kube-scheduler deployment to use config
kubectl -n kube-system patch deployment kube-scheduler \
  --type=json -p='[
    {"op": "add", "path": "/spec/template/spec/containers/0/command/-", 
     "value": "--config=/etc/kubernetes/scheduler-config.yaml"},
    {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-",
     "value": {
       "name": "scheduler-config",
       "mountPath": "/etc/kubernetes/scheduler-config.yaml",
       "subPath": "config.yaml"
     }},
    {"op": "add", "path": "/spec/template/spec/volumes/-",
     "value": {
       "name": "scheduler-config",
       "configMap": {"name": "scheduler-config"}
     }}
  ]'
```

**Verify Bin Packing**:

```bash
# Check pod distribution (should be concentrated on fewer nodes)
kubectl get pods -A -o wide | awk '{print $8}' | sort | uniq -c | sort -rn

# Check node utilization
kubectl top nodes
```

**Expected Result**: Pods should be concentrated on fewer nodes with higher utilization (70-80% CPU/memory), leaving other nodes available for new workloads.

#### 4. Schedule Platform Pods in Dedicated Node Pool or Using Anti-Affinity

**Why**: Isolates platform services from user workloads, ensures platform services have dedicated resources, and improves reliability.

**Action Items**:

**Option A: Dedicated Node Pool with Taints**:

```yaml
# 1. Label and taint nodes for platform services
kubectl label nodes <node-name> node-role=platform
kubectl taint nodes <node-name> platform-only=true:NoSchedule

# 2. Add toleration to platform pod deployments
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  template:
    spec:
      tolerations:
      - key: platform-only
        operator: Equal
        value: "true"
        effect: NoSchedule
      nodeSelector:
        node-role: platform
      containers:
      - name: prometheus
        # ... container spec
```

**Option B: Pod Anti-Affinity**:

```yaml
# Distribute platform pods across nodes for HA
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 3
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - prometheus
              topologyKey: kubernetes.io/hostname
          # Or use requiredDuringScheduling for strict distribution
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - prometheus
            topologyKey: kubernetes.io/hostname
```

**Option C: Node Affinity for Platform Services**:

```yaml
# Prefer platform nodes but allow fallback
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: node-role
                operator: In
                values:
                - platform
```

**Recommended Platform Services to Isolate**:
- Prometheus, Grafana, Alertmanager
- CAPI controllers
- etcd (if external)
- API server (if external)
- GitOps controllers (ArgoCD, Flux)
- Log aggregation (Loki, Fluentd)

#### 5. Update CAPI QPS and Other Settings Based on Load

**Why**: Default QPS limits (10-20) are too low for managing many clusters. Controllers will be throttled, slowing down cluster operations.

**Action Items**:

**Tier-Based QPS Configuration**:

| Tier | QPS | Burst | Cluster Concurrency | Machine Concurrency |
|------|-----|-------|---------------------|---------------------|
| **XS** | 30 | 50 | 20 | 20 |
| **S** | 50 | 100 | 50 | 50 |
| **M** | 100 | 200 | 100 | 100 |
| **L** | 200 | 400 | 200 | 200 |
| **XL+** | 500 | 1000 | 500 | 500 |

**Apply QPS Tuning**:

```bash
#!/bin/bash
# patch-capi-qps.sh
# Adjust based on your tier

TIER="M"  # Change to XS, S, M, L, or XL

case $TIER in
  XS)
    QPS=30
    BURST=50
    CLUSTER_CONCURRENCY=20
    MACHINE_CONCURRENCY=20
    ;;
  S)
    QPS=50
    BURST=100
    CLUSTER_CONCURRENCY=50
    MACHINE_CONCURRENCY=50
    ;;
  M)
    QPS=100
    BURST=200
    CLUSTER_CONCURRENCY=100
    MACHINE_CONCURRENCY=100
    ;;
  L)
    QPS=200
    BURST=400
    CLUSTER_CONCURRENCY=200
    MACHINE_CONCURRENCY=200
    ;;
  XL)
    QPS=500
    BURST=1000
    CLUSTER_CONCURRENCY=500
    MACHINE_CONCURRENCY=500
    ;;
esac

# Patch CAPI Core Controller
kubectl -n capi-system patch deployment capi-controller-manager \
  --type=json -p="[
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--kube-api-qps=$QPS\"},
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--kube-api-burst=$BURST\"},
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--cluster-concurrency=$CLUSTER_CONCURRENCY\"},
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--machine-concurrency=$MACHINE_CONCURRENCY\"}
  ]"

# Patch Kubeadm Control Plane Controller
kubectl -n capi-kubeadm-control-plane-system patch deployment \
  capi-kubeadm-control-plane-controller-manager \
  --type=json -p="[
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--kube-api-qps=$QPS\"},
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--kube-api-burst=$BURST\"},
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--kubeadmcontrolplane-concurrency=$CLUSTER_CONCURRENCY\"}
  ]"

# Patch Bootstrap Controller
kubectl -n capi-kubeadm-bootstrap-system patch deployment \
  capi-kubeadm-bootstrap-controller-manager \
  --type=json -p="[
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--kube-api-qps=$QPS\"},
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--kube-api-burst=$BURST\"},
    {\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args/-\", \"value\": \"--kubeadmconfig-concurrency=$MACHINE_CONCURRENCY\"}
  ]"

echo "✓ CAPI controllers patched for tier $TIER"
```

**Monitor QPS Usage**:

```bash
# Check for rate limiting (429 errors)
kubectl logs -n capi-system deployment/capi-controller-manager | grep "429"

# Monitor API server request rate
kubectl get --raw /metrics | grep apiserver_request_total
```

#### 6. Tightly Monitor Resource Utilization

**Why**: Early detection of resource constraints prevents failures and allows proactive scaling.

**Action Items**:

**Key Metrics to Monitor**:

1. **Controller Metrics**:
   - Reconcile duration (p50, p95, p99)
   - Work queue depth
   - Reconcile errors
   - CPU and memory usage

2. **API Server Metrics**:
   - Request latency (p50, p95, p99)
   - Request rate (QPS)
   - Error rate (429, 5xx)
   - In-flight requests

3. **etcd Metrics**:
   - Database size
   - WAL fsync latency
   - Leader changes
   - Peer round-trip time

4. **Node Metrics**:
   - CPU utilization
   - Memory utilization
   - Disk I/O
   - Network I/O

**Prometheus Alerts**:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: capi-scaling-alerts
spec:
  groups:
  - name: capi-scaling
    rules:
    # Controller reconcile latency
    - alert: HighReconcileLatency
      expr: histogram_quantile(0.99, 
            sum(rate(controller_runtime_reconcile_time_seconds_bucket[5m])) 
            by (controller, le)) > 60
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Controller {{ $labels.controller }} reconcile p99 > 60s"
        
    # Work queue backlog
    - alert: WorkQueueBacklog
      expr: workqueue_depth{name=~"cluster|machine"} > 100
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Work queue {{ $labels.name }} depth > 100"
        
    # API server latency
    - alert: APIServerHighLatency
      expr: histogram_quantile(0.99,
            sum(rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m]))
            by (verb, le)) > 2
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "API server {{ $labels.verb }} p99 latency > 2s"
        
    # etcd database size
    - alert: EtcdDatabaseSizeHigh
      expr: etcd_mvcc_db_total_size_in_bytes > 6442450944  # 6 GB
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "etcd database size high: {{ $value | humanize1024 }}"
        
    # Node CPU high
    - alert: NodeCPUHigh
      expr: (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 0.8
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Node {{ $labels.instance }} CPU > 80%"
        
    # Node memory high
    - alert: NodeMemoryHigh
      expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.85
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Node {{ $labels.instance }} memory > 85%"
```

**Grafana Dashboard Queries**:

```promql
# Controller reconcile rate
sum(rate(controller_runtime_reconcile_total[5m])) by (controller)

# Controller reconcile duration (p99)
histogram_quantile(0.99, 
  sum(rate(controller_runtime_reconcile_time_seconds_bucket[5m])) 
  by (controller, le))

# Work queue depth
workqueue_depth{name=~"cluster|machine"}

# API server request rate
sum(rate(apiserver_request_total[5m])) by (verb, resource)

# etcd database size
etcd_mvcc_db_total_size_in_bytes

# Node resource utilization
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Commands for Manual Monitoring**:

```bash
# Check controller resource usage
kubectl top pods -n capi-system

# Check node resource usage
kubectl top nodes

# Check etcd database size
kubectl exec -n kube-system etcd-<node-name> -- etcdctl endpoint status \
  --write-out=json | jq '.[] | {dbSize: .Status.dbSize}'

# Check API server metrics
kubectl get --raw /metrics | grep apiserver_request

# Check for pending pods (resource constraints)
kubectl get pods -A --field-selector=status.phase=Pending
```

---

## Additional Scaling Strategies

### 7. Implement Horizontal Pod Autoscaling (HPA)

**Why**: Automatically scale controllers based on load.

**Action Items**:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: capi-controller-manager
  namespace: capi-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: capi-controller-manager
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 30
      selectPolicy: Max
```

### 8. Enable etcd Auto-Compaction

**Why**: Prevents etcd database from growing unbounded.

**Action Items**:

```yaml
# Add to etcd static pod manifest
# /etc/kubernetes/manifests/etcd.yaml
spec:
  containers:
  - name: etcd
    command:
    - etcd
    - --auto-compaction-mode=periodic
    - --auto-compaction-retention=1h  # Compact every hour
    - --quota-backend-bytes=8589934592  # 8 GB (default 2 GB)
```

### 9. Use ClusterClass for Standardization

**Why**: Reduces API server load by using templates instead of individual cluster definitions.

**Action Items**:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: ClusterClass
metadata:
  name: standard-production
spec:
  controlPlane:
    ref:
      apiVersion: controlplane.cluster.x-k8s.io/v1beta1
      kind: KubeadmControlPlaneTemplate
      name: control-plane-template
  workers:
    machineDeployments:
    - class: default-worker
      template:
        bootstrap:
          ref:
            apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
            kind: KubeadmConfigTemplate
            name: worker-bootstrap
        infrastructure:
          ref:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
            kind: NutanixMachineTemplate
            name: worker-machine
```

### 10. Implement Namespace Sharding (Large Scale)

**Why**: Distributes controller load across multiple controller instances.

**Action Items**:

```yaml
# Deploy multiple controller instances, each watching specific namespaces
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

### 11. Configure API Priority and Fairness (APF)

**Why**: Ensures CAPI controllers get priority access to API server.

**Action Items**:

```yaml
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: PriorityLevelConfiguration
metadata:
  name: cluster-api-priority
spec:
  type: Limited
  limited:
    nominalConcurrencyShares: 100
    limitResponse:
      type: Queue
      queuing:
        queues: 64
        handSize: 6
        queueLengthLimit: 50
---
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
    resourceRules:
    - resources: ["clusters", "machines", "machinesets"]
      apiGroups: ["cluster.x-k8s.io"]
      verbs: ["*"]
```

### 12. Optimize Controller Sync Period

**Why**: Reduces periodic reconciliation load.

**Action Items**:

```bash
# Increase sync period for large scale (default 10m, increase to 30m)
kubectl -n capi-system patch deployment capi-controller-manager \
  --type=json -p='[
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", 
     "value": "--sync-period=30m"}
  ]'
```

### 13. Use Vertical Pod Autoscaling (VPA)

**Why**: Automatically adjusts resource requests/limits based on actual usage.

**Action Items**:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: capi-controller-manager
  namespace: capi-system
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: capi-controller-manager
  updatePolicy:
    updateMode: "Auto"  # Or "Off" for recommendations only
  resourcePolicy:
    containerPolicies:
    - containerName: manager
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 4000m
        memory: 8Gi
```

### 14. Implement Pod Disruption Budgets (PDB)

**Why**: Ensures minimum availability during node maintenance or failures.

**Action Items**:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: capi-controller-manager
  namespace: capi-system
spec:
  minAvailable: 1  # Or use maxUnavailable: 1
  selector:
    matchLabels:
      control-plane: controller-manager
      app: cluster-api
```

### 15. Enable Node Autoscaling

**Why**: Automatically adds nodes when resource pressure is detected.

**Action Items**:

```yaml
# Cluster Autoscaler configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-status
  namespace: kube-system
data:
  nodes.min: "3"
  nodes.max: "20"
  scale-down-delay-after-add: "10m"
  scale-down-unneeded-time: "10m"
  scale-down-utilization-threshold: "0.5"
```

---

## Observability Stack Scaling (Prometheus, Loki, Logging Operator, etcd)

Observability components (Prometheus, Loki, logging operators) are memory-intensive and require special scaling strategies. This section covers tier-specific configurations and optimization techniques.

### Memory Consumption Overview

| Component | Memory Usage Pattern | Primary Memory Consumers |
|-----------|---------------------|---------------------------|
| **Prometheus** | Grows with metrics cardinality | TSDB (time-series database), active series, chunks |
| **Loki** | Grows with log volume | Ingest buffers, chunk storage, index cache |
| **Logging Operator** | Moderate | Log forwarding buffers, processing queues |
| **etcd** | Grows with object count | Watch connections, database size, index |

### Tier-Based Resource Sizing

| Tier | Prometheus | Loki | Logging Operator | etcd (Observability) |
|------|------------|------|------------------|---------------------|
| **XS** | 2 CPU, 4 Gi | 1 CPU, 2 Gi | 500m CPU, 1 Gi | 2 CPU, 8 Gi |
| **S** | 4 CPU, 8 Gi | 2 CPU, 4 Gi | 1 CPU, 2 Gi | 4 CPU, 16 Gi |
| **M** | 8 CPU, 16 Gi | 4 CPU, 8 Gi | 2 CPU, 4 Gi | 8 CPU, 32 Gi |
| **L** | 16 CPU, 32 Gi | 8 CPU, 16 Gi | 4 CPU, 8 Gi | 16 CPU, 64 Gi |
| **XL+** | Sharded/Federated | Distributed | Multiple instances | External cluster |

---

## Prometheus Scaling Strategies

### Strategy 1: Single Prometheus (XS-S Tier)

**Configuration**:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.48.0
        args:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus'
        - '--storage.tsdb.retention.time=15d'  # Reduce retention for memory
        - '--storage.tsdb.retention.size=50GB'  # Limit storage size
        - '--storage.tsdb.max-block-duration=2h'  # Smaller blocks = less memory
        - '--storage.tsdb.min-block-duration=2h'
        - '--web.enable-lifecycle'
        - '--web.console.libraries=/usr/share/prometheus/console_libraries'
        - '--web.console.templates=/usr/share/prometheus/consoles'
        # Memory optimization flags
        - '--storage.tsdb.wal-compression'  # Compress WAL to save memory
        - '--query.max-concurrency=20'  # Limit concurrent queries
        - '--query.max-samples=50000000'  # Limit query samples
        - '--query.timeout=2m'  # Query timeout
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
          limits:
            cpu: "8"
            memory: "16Gi"
        volumeMounts:
        - name: prometheus-storage
          mountPath: /prometheus
  volumeClaimTemplates:
  - metadata:
      name: prometheus-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 100Gi
```

**Memory Optimization Techniques**:

1. **Reduce Retention Period**:
   ```yaml
   - '--storage.tsdb.retention.time=7d'  # Shorter retention = less memory
   ```

2. **Limit Storage Size**:
   ```yaml
   - '--storage.tsdb.retention.size=30GB'  # Hard limit on disk usage
   ```

3. **Enable WAL Compression**:
   ```yaml
   - '--storage.tsdb.wal-compression'  # Reduces memory usage
   ```

4. **Reduce Block Duration**:
   ```yaml
   - '--storage.tsdb.max-block-duration=2h'  # Smaller blocks = less memory per block
   ```

### Strategy 2: Prometheus Sharding (M-L Tier)

**Why**: Distribute scrape load across multiple Prometheus instances.

**Configuration**:

```yaml
# Prometheus Shard 1 (CAPI metrics)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus-shard-1
  namespace: monitoring
  labels:
    prometheus-shard: "1"
spec:
  replicas: 1
  serviceName: prometheus-shard-1
  template:
    spec:
      containers:
      - name: prometheus
        args:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus'
        - '--storage.tsdb.retention.time=30d'
        - '--storage.tsdb.retention.size=100GB'
        - '--storage.tsdb.wal-compression'
        - '--web.external-url=http://prometheus-shard-1:9090'
        resources:
          requests:
            cpu: "8"
            memory: "16Gi"
          limits:
            cpu: "16"
            memory: "32Gi"
---
# Prometheus Shard 2 (Node/System metrics)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus-shard-2
  namespace: monitoring
  labels:
    prometheus-shard: "2"
spec:
  replicas: 1
  serviceName: prometheus-shard-2
  template:
    spec:
      containers:
      - name: prometheus
        args:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus'
        - '--storage.tsdb.retention.time=30d'
        - '--storage.tsdb.retention.size=100GB'
        - '--storage.tsdb.wal-compression'
        - '--web.external-url=http://prometheus-shard-2:9090'
        resources:
          requests:
            cpu: "8"
            memory: "16Gi"
          limits:
            cpu: "16"
            memory: "32Gi"
```

**ServiceMonitor Sharding**:

```yaml
# Scrape only CAPI-related metrics
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: capi-metrics
  namespace: monitoring
  labels:
    prometheus-shard: "1"
spec:
  selector:
    matchLabels:
      app: cluster-api
  endpoints:
  - port: https
    interval: 30s
---
# Scrape only node/system metrics
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: node-metrics
  namespace: monitoring
  labels:
    prometheus-shard: "2"
spec:
  selector:
    matchLabels:
      k8s-app: node-exporter
  endpoints:
  - port: metrics
    interval: 30s
```

**Prometheus Operator Configuration**:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus-shard-1
  namespace: monitoring
spec:
  shards: 1
  replicas: 1
  retention: 30d
  retentionSize: 100GB
  walCompression: true
  serviceMonitorSelector:
    matchLabels:
      prometheus-shard: "1"
  resources:
    requests:
      cpu: "8"
      memory: "16Gi"
    limits:
      cpu: "16"
      memory: "32Gi"
  storage:
    volumeClaimTemplate:
      spec:
        resources:
          requests:
            storage: 200Gi
```

### Strategy 3: Thanos for Long-Term Storage (L-XL+ Tier)

**Why**: Offloads long-term storage to object storage, reduces Prometheus memory.

**Architecture**:

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│   Prometheus    │────▶│ Thanos       │────▶│ Object      │
│   (30d retention)│     │ Sidecar      │     │ Storage     │
└─────────────────┘     └──────────────┘     └─────────────┘
                                │
                                ▼
                         ┌──────────────┐
                         │ Thanos Query │
                         │ (Federation)│
                         └──────────────┘
```

**Prometheus with Thanos Sidecar**:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus
  namespace: monitoring
spec:
  template:
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.48.0
        args:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus'
        - '--storage.tsdb.retention.time=30d'  # Short retention, long-term in object storage
        - '--storage.tsdb.retention.size=50GB'
        - '--storage.tsdb.wal-compression'
        - '--web.enable-admin-api'  # Required for Thanos
        - '--web.enable-lifecycle'
        resources:
          requests:
            cpu: "8"
            memory: "16Gi"  # Reduced due to shorter retention
          limits:
            cpu: "16"
            memory: "32Gi"
      - name: thanos-sidecar
        image: quay.io/thanos/thanos:v0.32.5
        args:
        - sidecar
        - --prometheus.url=http://localhost:9090
        - --tsdb.path=/prometheus
        - --objstore.config-file=/etc/thanos/storage.yaml
        - --http-address=0.0.0.0:10902
        - --grpc-address=0.0.0.0:10901
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
        volumeMounts:
        - name: thanos-storage-config
          mountPath: /etc/thanos
      volumes:
      - name: thanos-storage-config
        configMap:
          name: thanos-storage-config
```

**Thanos Query (Federation)**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query
  namespace: monitoring
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: thanos-query
        image: quay.io/thanos/thanos:v0.32.5
        args:
        - query
        - --http-address=0.0.0.0:10902
        - --grpc-address=0.0.0.0:10901
        - --query.replica-label=replica
        - --store=prometheus:10901
        - --store=thanos-store:10901
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
```

**Memory Benefits**:
- Prometheus retention reduced from 90d to 30d → **~60% memory reduction**
- Long-term data in object storage (S3, GCS, Nutanix Objects)
- Query federation across multiple Prometheus instances

### Prometheus Memory Optimization Checklist

- [ ] **Enable WAL compression** (`--storage.tsdb.wal-compression`)
- [ ] **Reduce retention period** (30d instead of 90d+)
- [ ] **Set storage size limits** (`--storage.tsdb.retention.size`)
- [ ] **Reduce block duration** (2h instead of 2d)
- [ ] **Limit query concurrency** (`--query.max-concurrency`)
- [ ] **Limit query samples** (`--query.max-samples`)
- [ ] **Use recording rules** to pre-aggregate metrics
- [ ] **Drop high-cardinality metrics** (use `metric_relabel_configs`)
- [ ] **Shard by metric type** (CAPI, nodes, apps)
- [ ] **Use Thanos** for long-term storage (L+ tiers)

---

## Thanos: Comprehensive Scaling Guide

Thanos is a highly available, long-term storage solution for Prometheus that enables global querying, unlimited retention, and horizontal scaling. This section covers complete Thanos deployment strategies across all tiers.

### Thanos Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          THANOS ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐            │
│  │ Prometheus 1  │     │ Prometheus 2 │     │ Prometheus N │            │
│  │ + Sidecar    │     │ + Sidecar    │     │ + Sidecar    │            │
│  └──────┬───────┘     └──────┬───────┘     └──────┬───────┘            │
│         │                     │                     │                     │
│         └─────────────────────┼─────────────────────┘                  │
│                               │                                         │
│                               ▼                                         │
│                    ┌─────────────────────┐                              │
│                    │   Object Storage     │                              │
│                    │  (S3/GCS/Nutanix)   │                              │
│                    └──────────┬──────────┘                              │
│                               │                                         │
│         ┌─────────────────────┼─────────────────────┐                  │
│         │                     │                     │                     │
│         ▼                     ▼                     ▼                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                │
│  │ Thanos Store  │   │ Thanos Query │   │ Thanos       │                │
│  │ (caching)     │   │ (federation)│   │ Compactor    │                │
│  └──────────────┘   └──────────────┘   └──────────────┘                │
│         │                     │                     │                     │
│         └─────────────────────┼─────────────────────┘                  │
│                               │                                         │
│                               ▼                                         │
│                    ┌─────────────────────┐                              │
│                    │   Grafana / Users   │                              │
│                    └─────────────────────┘                              │
└─────────────────────────────────────────────────────────────────────────┘
```

### Thanos Components

| Component | Purpose | Memory Usage | When to Deploy |
|-----------|---------|--------------|----------------|
| **Sidecar** | Uploads Prometheus blocks to object storage | Low (~1 Gi) | Always (with Prometheus) |
| **Query** | Federates queries across Prometheus/Store | Medium (~4-8 Gi) | M+ tier |
| **Store** | Caches object storage data | High (~8-16 Gi) | L+ tier |
| **Compactor** | Downsamples and compacts blocks | Medium (~4-8 Gi) | L+ tier |
| **Ruler** | Evaluates recording/alerting rules | Low (~2 Gi) | Optional |
| **Receive** | Receives remote write from Prometheus | Medium (~4 Gi) | Alternative to Sidecar |

---

## Thanos Deployment Strategies by Tier

### Strategy 1: Thanos Sidecar Only (M Tier)

**Use Case**: Single Prometheus with long-term storage, no federation needed.

**Configuration**:

```yaml
# Prometheus with Thanos Sidecar
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  serviceName: prometheus
  template:
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.48.0
        args:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus'
        - '--storage.tsdb.retention.time=30d'  # Short retention
        - '--storage.tsdb.retention.size=50GB'
        - '--storage.tsdb.wal-compression'
        - '--web.enable-admin-api'  # Required for Thanos
        - '--web.enable-lifecycle'
        resources:
          requests:
            cpu: "8"
            memory: "16Gi"  # Reduced from 32Gi due to shorter retention
          limits:
            cpu: "16"
            memory: "32Gi"
        volumeMounts:
        - name: prometheus-storage
          mountPath: /prometheus
      - name: thanos-sidecar
        image: quay.io/thanos/thanos:v0.32.5
        args:
        - sidecar
        - --prometheus.url=http://localhost:9090
        - --tsdb.path=/prometheus
        - --objstore.config-file=/etc/thanos/storage.yaml
        - --http-address=0.0.0.0:10902
        - --grpc-address=0.0.0.0:10901
        - --shipper.upload-compacted  # Upload compacted blocks
        - --reloader.config-file=/etc/prometheus/prometheus.yml
        - --reloader.config-envsubst-file=/etc/prometheus/prometheus.yml
        - --reloader.rule-dir=/etc/prometheus/rules
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
        volumeMounts:
        - name: prometheus-storage
          mountPath: /prometheus
          readOnly: true
        - name: thanos-storage-config
          mountPath: /etc/thanos
      volumes:
      - name: thanos-storage-config
        secret:
          secretName: thanos-storage-config
  volumeClaimTemplates:
  - metadata:
      name: prometheus-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 200Gi
```

**Object Storage Configuration** (Secret):

```yaml
# thanos-storage-config.yaml (create as Secret)
apiVersion: v1
kind: Secret
metadata:
  name: thanos-storage-config
  namespace: monitoring
type: Opaque
stringData:
  storage.yaml: |
    type: S3
    config:
      bucket: thanos-data
      endpoint: s3.amazonaws.com
      region: us-east-1
      access_key: <access-key>
      secret_key: <secret-key>
      # Or use Nutanix Objects
      # endpoint: <nutanix-objects-endpoint>
      # s3forcepathstyle: true
      insecure: false
      signature_version2: false
      encrypt_sse: false
      # Memory optimization
      part_size: 134217728  # 128MB chunks
      # Retry settings
      http_config:
        idle_conn_timeout: 90s
        response_header_timeout: 0s
        insecure_skip_verify: false
```

**Benefits**:
- Prometheus memory reduced by ~60% (30d retention vs 90d+)
- Unlimited retention in object storage
- Automatic block uploads every 2 hours
- No additional components needed

---

### Strategy 2: Thanos Query + Sidecar (M-L Tier)

**Use Case**: Multiple Prometheus instances, need unified querying.

**Thanos Query Deployment**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query
  namespace: monitoring
spec:
  replicas: 2  # HA
  template:
    metadata:
      labels:
        app: thanos-query
    spec:
      containers:
      - name: thanos-query
        image: quay.io/thanos/thanos:v0.32.5
        args:
        - query
        - --http-address=0.0.0.0:10902
        - --grpc-address=0.0.0.0:10901
        - --query.replica-label=replica
        - --query.replica-label=prometheus_replica
        # Store endpoints (Prometheus sidecars)
        - --store=dnssrv+_grpc._tcp.prometheus.monitoring.svc.cluster.local
        # Object storage (for historical data)
        - --store=dnssrv+_grpc._tcp.thanos-store.monitoring.svc.cluster.local
        # Query optimization
        - --query.timeout=5m
        - --query.max-concurrent=20
        - --query.max-concurrent-select=10
        - --query.default-evaluation-interval=15s
        - --query.lookback-delta=15m
        - --query.auto-downsampling
        # Caching
        - --query.cache-compression-type=snappy
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
        ports:
        - name: http
          containerPort: 10902
        - name: grpc
          containerPort: 10901
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /-/ready
            port: http
          initialDelaySeconds: 30
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: thanos-query
  namespace: monitoring
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 10902
    targetPort: http
  - name: grpc
    port: 10901
    targetPort: grpc
  selector:
    app: thanos-query
```

**Prometheus Service (for DNS discovery)**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
  annotations:
    # Enable DNS discovery for Thanos Query
    prometheus.io/scrape: "true"
spec:
  clusterIP: None  # Headless service for DNS SRV
  ports:
  - name: grpc
    port: 10901
    targetPort: 10901
  selector:
    app: prometheus
```

**Benefits**:
- Unified querying across multiple Prometheus instances
- Automatic deduplication of replicas
- Query both recent (Prometheus) and historical (Store) data
- HA with multiple Query replicas

---

### Strategy 3: Complete Thanos Stack (L-XL+ Tier)

**Use Case**: Large-scale, long-term retention, multi-cluster federation.

**Thanos Store (Caching Layer)**:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-store
  namespace: monitoring
spec:
  replicas: 2  # HA
  serviceName: thanos-store
  template:
    metadata:
      labels:
        app: thanos-store
    spec:
      containers:
      - name: thanos-store
        image: quay.io/thanos/thanos:v0.32.5
        args:
        - store
        - --data-dir=/var/thanos/store
        - --objstore.config-file=/etc/thanos/storage.yaml
        - --http-address=0.0.0.0:10902
        - --grpc-address=0.0.0.0:10901
        # Index cache (memory optimization)
        - --index-cache-size=2GB  # Limit index cache
        - --index-cache.config-file=/etc/thanos/index-cache.yaml
        # Chunk cache
        - --chunk-pool-size=2GB  # Limit chunk cache
        # Query optimization
        - --store.grpc.series-max-concurrency=20
        - --store.grpc.series-sample-limit=0  # No limit
        # Sync settings
        - --sync-block-duration=3m
        - --block-sync-concurrency=20
        - --min-time=-2w  # Only cache last 2 weeks
        - --max-time=0h   # Current time
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
          limits:
            cpu: "8"
            memory: "16Gi"
        volumeMounts:
        - name: thanos-store-data
          mountPath: /var/thanos/store
        - name: thanos-storage-config
          mountPath: /etc/thanos
        - name: thanos-index-cache-config
          mountPath: /etc/thanos
      volumes:
      - name: thanos-storage-config
        secret:
          secretName: thanos-storage-config
      - name: thanos-index-cache-config
        configMap:
          name: thanos-index-cache-config
  volumeClaimTemplates:
  - metadata:
      name: thanos-store-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 100Gi  # For index cache
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: thanos-index-cache-config
  namespace: monitoring
data:
  index-cache.yaml: |
    type: IN-MEMORY
    config:
      max_size: 2GB
      max_item_size: 50MB
---
apiVersion: v1
kind: Service
metadata:
  name: thanos-store
  namespace: monitoring
spec:
  clusterIP: None  # Headless for DNS SRV
  ports:
  - name: http
    port: 10902
    targetPort: http
  - name: grpc
    port: 10901
    targetPort: grpc
  selector:
    app: thanos-store
```

**Thanos Compactor (Downsampling & Compaction)**:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-compactor
  namespace: monitoring
spec:
  replicas: 1  # Single instance (leader election)
  serviceName: thanos-compactor
  template:
    metadata:
      labels:
        app: thanos-compactor
    spec:
      containers:
      - name: thanos-compactor
        image: quay.io/thanos/thanos:v0.32.5
        args:
        - compact
        - --data-dir=/var/thanos/compact
        - --objstore.config-file=/etc/thanos/storage.yaml
        - --http-address=0.0.0.0:10902
        - --wait
        # Retention policies
        - --retention.resolution-raw=30d      # Keep raw data 30 days
        - --retention.resolution-5m=90d      # Keep 5m downsampled 90 days
        - --retention.resolution-1h=365d     # Keep 1h downsampled 1 year
        # Compaction settings
        - --compact.concurrency=4
        - --downsample.concurrency=4
        - --block-sync-concurrency=20
        # Consistency checks
        - --consistency-delay=30m
        - --delete-delay=48h
        # Memory optimization
        - --compact.block-size-limit=40GB
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
          limits:
            cpu: "8"
            memory: "16Gi"
        volumeMounts:
        - name: thanos-compact-data
          mountPath: /var/thanos/compact
        - name: thanos-storage-config
          mountPath: /etc/thanos
      volumes:
      - name: thanos-storage-config
        secret:
          secretName: thanos-storage-config
  volumeClaimTemplates:
  - metadata:
      name: thanos-compact-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 200Gi  # For compaction workspace
```

**Thanos Ruler (Recording & Alerting Rules)**:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-ruler
  namespace: monitoring
spec:
  replicas: 2  # HA
  serviceName: thanos-ruler
  template:
    metadata:
      labels:
        app: thanos-ruler
    spec:
      containers:
      - name: thanos-ruler
        image: quay.io/thanos/thanos:v0.32.5
        args:
        - rule
        - --data-dir=/var/thanos/ruler
        - --objstore.config-file=/etc/thanos/storage.yaml
        - --http-address=0.0.0.0:10902
        - --grpc-address=0.0.0.0:10901
        # Query endpoints
        - --query=dnssrv+_grpc._tcp.thanos-query.monitoring.svc.cluster.local
        # Rule files
        - --rule-file=/etc/thanos/rules/*.yaml
        # Evaluation settings
        - --eval-interval=30s
        - --tsdb.block-duration=2h
        - --tsdb.retention=30d
        # Alertmanager
        - --alertmanagers.url=http://alertmanager:9093
        - --alert.query-url=http://thanos-query:10902
        # Memory optimization
        - --query.max-concurrent=10
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
        volumeMounts:
        - name: thanos-ruler-data
          mountPath: /var/thanos/ruler
        - name: thanos-storage-config
          mountPath: /etc/thanos
        - name: thanos-rules
          mountPath: /etc/thanos/rules
      volumes:
      - name: thanos-storage-config
        secret:
          secretName: thanos-storage-config
      - name: thanos-rules
        configMap:
          name: thanos-rules
  volumeClaimTemplates:
  - metadata:
      name: thanos-ruler-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 50Gi
```

**Complete Thanos Query (with all stores)**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query
  namespace: monitoring
spec:
  replicas: 3  # HA + load distribution
  template:
    spec:
      containers:
      - name: thanos-query
        image: quay.io/thanos/thanos:v0.32.5
        args:
        - query
        - --http-address=0.0.0.0:10902
        - --grpc-address=0.0.0.0:10901
        - --query.replica-label=replica
        - --query.replica-label=prometheus_replica
        # All store endpoints
        - --store=dnssrv+_grpc._tcp.prometheus.monitoring.svc.cluster.local
        - --store=dnssrv+_grpc._tcp.thanos-store.monitoring.svc.cluster.local
        - --store=dnssrv+_grpc._tcp.thanos-ruler.monitoring.svc.cluster.local
        # Query optimization
        - --query.timeout=5m
        - --query.max-concurrent=30
        - --query.max-concurrent-select=15
        - --query.default-evaluation-interval=15s
        - --query.lookback-delta=15m
        - --query.auto-downsampling
        # Caching
        - --query.cache-compression-type=snappy
        # Query frontend (if using)
        - --query.frontend.address=dnssrv+_http._tcp.thanos-query-frontend.monitoring.svc.cluster.local
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
          limits:
            cpu: "8"
            memory: "16Gi"
```

---

## Thanos Memory Optimization

### Sidecar Optimization

```yaml
# Optimize Thanos Sidecar memory
args:
- sidecar
- --prometheus.url=http://localhost:9090
- --tsdb.path=/prometheus
- --objstore.config-file=/etc/thanos/storage.yaml
# Memory optimization
- --shipper.upload-compacted  # Upload compacted blocks (smaller)
- --min-time=-2h  # Only upload blocks older than 2h
# Upload optimization
- --block-sync-concurrency=10  # Limit concurrent uploads
- --upload-compacted-block-size-limit=40GB  # Limit block size
```

### Store Optimization

```yaml
# Limit Store memory usage
args:
- store
- --index-cache-size=2GB  # Limit index cache
- --chunk-pool-size=2GB    # Limit chunk cache
- --min-time=-2w           # Only cache recent data
- --max-time=0h           # Current time
- --store.grpc.series-max-concurrency=20  # Limit concurrent queries
```

### Query Optimization

```yaml
# Optimize Query memory
args:
- query
- --query.max-concurrent=20        # Limit concurrent queries
- --query.max-concurrent-select=10  # Limit concurrent selects
- --query.timeout=5m                # Query timeout
- --query.auto-downsampling        # Use downsampled data when possible
```

---

## Thanos Tier-Specific Configurations

### M Tier (50-200 Clusters)

| Component | Replicas | CPU | Memory | Storage |
|-----------|----------|-----|--------|---------|
| Prometheus + Sidecar | 2-3 | 8 | 16 Gi | 200 Gi |
| Thanos Query | 2 | 2 | 4 Gi | - |
| **Total** | - | **20-26** | **36-52 Gi** | **400-600 Gi** |

**Configuration**:
- Prometheus: 30d retention, sharded (2-3 shards)
- Sidecar: Uploads to object storage
- Query: Federates queries, no Store needed

### L Tier (200-1,000 Clusters)

| Component | Replicas | CPU | Memory | Storage |
|-----------|----------|-----|--------|---------|
| Prometheus + Sidecar | 3-4 | 8 | 16 Gi | 200 Gi |
| Thanos Query | 3 | 4 | 8 Gi | - |
| Thanos Store | 2 | 4 | 8 Gi | 100 Gi |
| Thanos Compactor | 1 | 4 | 8 Gi | 200 Gi |
| **Total** | - | **52-68** | **80-112 Gi** | **1.0-1.2 Ti** |

**Configuration**:
- Prometheus: 30d retention, sharded (3-4 shards)
- Store: Caches last 2 weeks from object storage
- Compactor: Downsamples to 5m/1h resolutions
- Query: Queries all stores

### XL+ Tier (1,000+ Clusters)

| Component | Replicas | CPU | Memory | Storage |
|-----------|----------|-----|--------|---------|
| Prometheus + Sidecar | 5+ | 8 | 16 Gi | 200 Gi |
| Thanos Query | 5+ | 8 | 16 Gi | - |
| Thanos Store | 3+ | 8 | 16 Gi | 200 Gi |
| Thanos Compactor | 2 | 8 | 16 Gi | 500 Gi |
| Thanos Ruler | 2 | 4 | 8 Gi | 100 Gi |
| **Total** | - | **140+** | **280+ Gi** | **2+ Ti** |

**Configuration**:
- Multi-region deployment
- Store: Regional caching
- Compactor: Global compaction
- Query: Global federation

---

## Thanos Object Storage Options

### AWS S3

```yaml
type: S3
config:
  bucket: thanos-data
  endpoint: s3.amazonaws.com
  region: us-east-1
  access_key: <key>
  secret_key: <secret>
  insecure: false
  signature_version2: false
  encrypt_sse: true
  sse_kms_key_id: <kms-key>
```

### Google Cloud Storage (GCS)

```yaml
type: GCS
config:
  bucket: thanos-data
  service_account: <service-account-json>
```

### Nutanix Objects (S3-Compatible)

```yaml
type: S3
config:
  bucket: thanos-data
  endpoint: <nutanix-objects-endpoint>
  access_key: <access-key>
  secret_key: <secret-key>
  s3forcepathstyle: true
  insecure: false
  signature_version2: false
```

### Azure Blob Storage

```yaml
type: AZURE
config:
  storage_account: <account>
  storage_account_key: <key>
  container: thanos-data
  endpoint: <endpoint>
```

---

## Thanos Monitoring & Alerts

### Prometheus Alerts for Thanos

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: thanos-alerts
  namespace: monitoring
spec:
  groups:
  - name: thanos
    rules:
    # Thanos Sidecar upload failures
    - alert: ThanosSidecarUploadFailures
      expr: rate(thanos_shipper_upload_failures_total[5m]) > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Thanos sidecar upload failures detected"
        
    # Thanos Store high memory
    - alert: ThanosStoreHighMemory
      expr: container_memory_working_set_bytes{pod=~"thanos-store.*"} / 
            container_spec_memory_limit_bytes{pod=~"thanos-store.*"} > 0.85
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Thanos Store memory usage > 85%"
        
    # Thanos Compactor lag
    - alert: ThanosCompactorLag
      expr: thanos_compactor_blocks_meta_sync_failures_total > 0
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Thanos Compactor falling behind"
        
    # Thanos Query high latency
    - alert: ThanosQueryHighLatency
      expr: histogram_quantile(0.99,
            sum(rate(thanos_query_api_instant_query_duration_seconds_bucket[5m]))
            by (le)) > 5
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Thanos Query p99 latency > 5s"
```

---

## Thanos Implementation Checklist

### Phase 1: Basic Setup (M Tier)

- [ ] **Deploy Prometheus with Sidecar**
- [ ] **Configure object storage** (S3/GCS/Nutanix Objects)
- [ ] **Verify block uploads** (check object storage)
- [ ] **Reduce Prometheus retention** (30d)
- [ ] **Monitor sidecar metrics**

### Phase 2: Federation (M-L Tier)

- [ ] **Deploy Thanos Query**
- [ ] **Configure DNS SRV discovery**
- [ ] **Update Grafana** to use Thanos Query
- [ ] **Test query federation**
- [ ] **Verify deduplication**

### Phase 3: Complete Stack (L-XL+ Tier)

- [ ] **Deploy Thanos Store** (caching layer)
- [ ] **Deploy Thanos Compactor** (downsampling)
- [ ] **Configure retention policies**
- [ ] **Deploy Thanos Ruler** (optional)
- [ ] **Set up multi-region** (if needed)
- [ ] **Configure monitoring & alerts**

### Phase 4: Optimization

- [ ] **Tune cache sizes** (Store index/chunk cache)
- [ ] **Optimize query concurrency**
- [ ] **Configure downsampling** (5m, 1h resolutions)
- [ ] **Set retention policies** (raw, 5m, 1h)
- [ ] **Monitor object storage costs**
- [ ] **Optimize block sizes**

---

## Thanos Benefits Summary

| Benefit | Impact |
|---------|--------|
| **Prometheus Memory Reduction** | ~60% reduction (30d vs 90d+ retention) |
| **Unlimited Retention** | Store years of data in object storage |
| **Global Querying** | Query across multiple Prometheus instances |
| **Cost Efficiency** | Object storage cheaper than local storage |
| **High Availability** | Multiple replicas, no single point of failure |
| **Downsampling** | Reduce storage costs by 90%+ for historical data |
| **Deduplication** | Automatic handling of Prometheus replicas |

---

## Loki Scaling Strategies

### Strategy 1: Single Loki (XS-S Tier)

**Configuration**:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: logging
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: loki
        image: grafana/loki:2.9.2
        args:
        - -config.file=/etc/loki/loki-config.yaml
        - -target=all
        env:
        - name: GOMAXPROCS
          value: "4"
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
        volumeMounts:
        - name: loki-config
          mountPath: /etc/loki
        - name: loki-storage
          mountPath: /loki
  volumeClaimTemplates:
  - metadata:
      name: loki-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 200Gi
```

**Loki Configuration (Memory Optimized)**:

```yaml
# loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: info

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
  - from: 2024-01-01
    store: tsdb
    object_store: filesystem
    schema: v13
    index:
      prefix: index_
      period: 24h

storage_config:
  tsdb_shipper:
    active_index_directory: /loki/tsdb-index
    cache_location: /loki/tsdb-cache
    cache_ttl: 24h
    query_ready_num_days: 7

compactor:
  working_directory: /loki/compactor
  shared_store: filesystem
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150

limits_config:
  ingestion_rate_mb: 50  # Limit ingestion rate
  ingestion_burst_size_mb: 100
  max_query_length: 721h  # 30 days
  max_query_parallelism: 32
  max_streams_per_user: 10000
  max_line_size: 256KB
  max_entries_limit_per_query: 10000
  max_cache_freshness_per_query: 10m
  per_stream_rate_limit: 10MB
  per_stream_rate_limit_burst: 20MB
  # Memory limits
  max_query_series: 500
  max_query_lookback: 0s
  max_concurrent_tail_requests: 10
  # Retention
  retention_period: 30d  # Reduce retention for memory
  # Chunk limits
  max_chunk_age: 1h
  chunk_target_size: 1048576  # 1MB
  chunk_retain_period: 15s
  # Index limits
  creation_grace_period: 10m
  max_query_parallelism: 32

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 30d

ruler:
  storage:
    type: local
    local:
      directory: /loki/rules
  rule_path: /loki/rules
  alertmanager_url: http://alertmanager:9093
  ring:
    kvstore:
      store: inmemory
  enable_api: true
```

### Strategy 2: Distributed Loki (M-L Tier)

**Why**: Separate components scale independently, better memory management.

**Architecture**:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Distributor │────▶│   Ingester   │────▶│   Storage   │
│   (stateless) │     │   (stateful) │     │   (S3/FS)   │
└─────────────┘     └─────────────┘     └─────────────┘
      │                    │
      ▼                    ▼
┌─────────────┐     ┌─────────────┐
│   Querier   │     │   Query     │
│   (read)    │     │   Frontend  │
└─────────────┘     └─────────────┘
```

**Distributor**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki-distributor
  namespace: logging
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: distributor
        image: grafana/loki:2.9.2
        args:
        - -config.file=/etc/loki/loki-config.yaml
        - -target=distributor
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2"
            memory: "2Gi"
```

**Ingester**:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki-ingester
  namespace: logging
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: ingester
        image: grafana/loki:2.9.2
        args:
        - -config.file=/etc/loki/loki-config.yaml
        - -target=ingester
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"  # Higher memory for chunk building
          limits:
            cpu: "4"
            memory: "8Gi"
```

**Querier**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loki-querier
  namespace: logging
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: querier
        image: grafana/loki:2.9.2
        args:
        - -config.file=/etc/loki/loki-config.yaml
        - -target=querier
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
```

**Loki Configuration (Distributed)**:

```yaml
# Distributed mode configuration
common:
  replication_factor: 3
  ring:
    kvstore:
      store: memberlist  # Use memberlist for ring

ingester:
  lifecycler:
    ring:
      kvstore:
        store: memberlist
    num_tokens: 512
    heartbeat_period: 5s
    observe_period: 10s
    join_after: 10s
    min_ready_duration: 15s
    final_wait: 30s
    # Memory optimization
    chunk_idle_period: 1h
    chunk_target_size: 1048576  # 1MB
    max_chunk_age: 1h
    flush_op_timeout: 10m
    max_transfer_retries: 0

querier:
  query_timeout: 5m
  max_concurrent: 20
  engine:
    timeout: 5m
    max_look_back_period: 0s

frontend:
  max_outstanding_per_tenant: 2048
  compress_responses: true
  query_stats_enabled: true

compactor:
  working_directory: /loki/compactor
  shared_store: s3
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
```

### Strategy 3: Loki with Object Storage (L-XL+ Tier)

**Why**: Offloads storage to S3/GCS/Nutanix Objects, reduces local memory.

**Configuration**:

```yaml
# Use S3-compatible storage (Nutanix Objects, AWS S3, etc.)
storage_config:
  aws:
    s3: s3://us-east-1/loki-chunks
    bucketnames: loki-chunks
    endpoint: s3.amazonaws.com
    region: us-east-1
    access_key_id: <key>
    secret_access_key: <secret>
    s3forcepathstyle: false
    insecure: false
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    cache_ttl: 24h
    shared_store: s3
    index_gateway_client:
      server_address: loki-index-gateway:9095

schema_config:
  configs:
  - from: 2024-01-01
    store: boltdb-shipper
    object_store: s3
    schema: v13
    index:
      prefix: index_
      period: 24h
```

**Memory Benefits**:
- Chunks stored in object storage → **reduced local memory**
- Index in object storage → **reduced index cache memory**
- Compactor runs separately → **reduced compaction memory**

### Loki Memory Optimization Checklist

- [ ] **Enable chunk compression** (reduces memory per chunk)
- [ ] **Reduce retention period** (30d instead of 90d+)
- [ ] **Limit ingestion rate** (`ingestion_rate_mb`)
- [ ] **Reduce chunk target size** (1MB instead of 5MB)
- [ ] **Reduce chunk idle period** (1h instead of 1d)
- [ ] **Use object storage** for chunks (S3, GCS, Nutanix Objects)
- [ ] **Distribute components** (separate ingester, querier, distributor)
- [ ] **Limit query parallelism** (`max_query_parallelism`)
- [ ] **Enable query frontend** (caching, query splitting)
- [ ] **Use index gateway** for large-scale deployments

---

## Logging Operator Scaling

### Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logging-operator
  namespace: logging
spec:
  replicas: 2  # HA
  template:
    spec:
      containers:
      - name: logging-operator
        image: banzaicloud/logging-operator:4.4.0
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2"
            memory: "2Gi"
        env:
        - name: WATCH_NAMESPACE
          value: ""  # Watch all namespaces
        - name: WORKER_THREADS
          value: "4"  # Increase for high log volume
```

### Fluentd/Fluent Bit Configuration

**Fluent Bit (Lightweight)**:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: logging
spec:
  template:
    spec:
      containers:
      - name: fluent-bit
        image: fluent/fluent-bit:2.2.0
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        volumeMounts:
        - name: fluent-bit-config
          mountPath: /fluent-bit/etc
      volumes:
      - name: fluent-bit-config
        configMap:
          name: fluent-bit-config
```

**Fluent Bit Config (Memory Optimized)**:

```ini
[SERVICE]
    Flush         5
    Daemon        Off
    Log_Level     info
    Parsers_File  parsers.conf
    # Memory limits
    Mem_Buf_Limit 50MB  # Limit buffer size
    storage.path  /var/log/flb-storage/
    storage.sync  normal
    storage.checksum  off
    storage.backlog.mem_limit  50M

[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    Parser            docker
    Tag               kube.*
    Refresh_Interval  5
    Mem_Buf_Limit     50MB  # Per-input buffer limit
    Skip_Long_Lines   On
    Skip_Empty_Lines  On

[FILTER]
    Name                kubernetes
    Match               kube.*
    Kube_URL            https://kubernetes.default.svc:443
    Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
    Kube_Tag_Prefix     kube.var.log.containers.
    Merge_Log           On
    Keep_Log            Off
    K8S-Logging.Parser  On
    K8S-Logging.Exclude Off
    # Memory optimization
    Buffer_Size         0  # Disable buffering
    Kube_Meta_Cache_TTL 3600

[OUTPUT]
    Name        http
    Match       *
    Host        loki.logging.svc
    Port        3100
    URI         /loki/api/v1/push
    Format      json
    Json_date_key    timestamp
    Json_date_format  %Y-%m-%dT%H:%M:%S.%NZ
    # Memory optimization
    Retry_Limit 3
    # Batch settings
    HTTP_Request_Header  X-Scope-OrgID tenant1
```

**Fluentd (For Complex Processing)**:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: fluentd-aggregator
  namespace: logging
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: fluentd
        image: fluent/fluentd:v1.16-debian-1
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "4"
            memory: "4Gi"
        env:
        - name: FLUENTD_CONF
          value: fluent.conf
        - name: BUFFER_QUEUE_LIMIT
          value: "32"  # Limit queue size
        - name: BUFFER_CHUNK_LIMIT_SIZE
          value: "8m"  # Smaller chunks
```

**Fluentd Config (Memory Optimized)**:

```xml
<source>
  @type forward
  port 24224
  bind 0.0.0.0
</source>

<filter **>
  @type record_transformer
  <record>
    cluster "${ENV['CLUSTER_NAME']}"
  </record>
</filter>

<match **>
  @type loki
  url http://loki:3100
  # Memory optimization
  buffer_type memory
  buffer_chunk_limit 8m  # Smaller chunks
  buffer_queue_limit 32  # Limit queue
  flush_interval 5s
  flush_at_shutdown true
  retry_limit 3
  slow_flush_log_threshold 20.0
  # Compression
  compress gzip
</match>
```

### Logging Operator Optimization Checklist

- [ ] **Use Fluent Bit** instead of Fluentd (lower memory footprint)
- [ ] **Limit buffer sizes** (`Mem_Buf_Limit`)
- [ ] **Reduce flush interval** (5s instead of 60s)
- [ ] **Enable compression** (gzip)
- [ ] **Limit retry attempts** (3 instead of unlimited)
- [ ] **Use batch processing** (reduce API calls)
- [ ] **Filter logs at source** (drop unnecessary logs)
- [ ] **Scale horizontally** (multiple aggregator instances)

---

## etcd Scaling for Observability Stack

### Dedicated etcd for Observability (L-XL+ Tier)

**Why**: Isolate observability data from Kubernetes control plane etcd.

**Configuration**:

```yaml
# External etcd cluster for observability
apiVersion: v1
kind: ConfigMap
metadata:
  name: etcd-observability-config
  namespace: monitoring
data:
  etcd.conf: |
    # etcd configuration for observability
    name: etcd-observability-0
    data-dir: /var/lib/etcd
    listen-client-urls: http://0.0.0.0:2379
    advertise-client-urls: http://etcd-observability-0:2379
    listen-peer-urls: http://0.0.0.0:2380
    initial-advertise-peer-urls: http://etcd-observability-0:2380
    initial-cluster: etcd-observability-0=http://etcd-observability-0:2380,etcd-observability-1=http://etcd-observability-1:2380,etcd-observability-2=http://etcd-observability-2:2380
    initial-cluster-token: observability-etcd-cluster
    initial-cluster-state: new
    # Memory optimization
    quota-backend-bytes: 8589934592  # 8 GB
    auto-compaction-mode: periodic
    auto-compaction-retention: 1h
    snapshot-count: 10000
    heartbeat-interval: 100
    election-timeout: 1000
    max-request-bytes: 1572864  # 1.5 MB
    grpc-keepalive-min-time: 5s
    grpc-keepalive-interval: 2h
    grpc-keepalive-timeout: 20s
```

**etcd StatefulSet**:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: etcd-observability
  namespace: monitoring
spec:
  replicas: 3
  serviceName: etcd-observability
  template:
    spec:
      containers:
      - name: etcd
        image: quay.io/coreos/etcd:v3.5.9
        command:
        - /usr/local/bin/etcd
        - --config-file=/etc/etcd/etcd.conf
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
          limits:
            cpu: "8"
            memory: "16Gi"
        volumeMounts:
        - name: etcd-config
          mountPath: /etc/etcd
        - name: etcd-data
          mountPath: /var/lib/etcd
      volumes:
      - name: etcd-config
        configMap:
          name: etcd-observability-config
  volumeClaimTemplates:
  - metadata:
      name: etcd-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 100Gi
```

### etcd Memory Optimization

**For Prometheus (if using etcd for service discovery)**:

```yaml
# Prometheus etcd service discovery
scrape_configs:
- job_name: 'etcd'
  etcd_sd_configs:
  - endpoints:
    - http://etcd-observability-0:2379
    - http://etcd-observability-1:2379
    - http://etcd-observability-2:2379
    # Reduce watch load
    refresh_interval: 30s  # Instead of 15s
```

**etcd Maintenance Script**:

```bash
#!/bin/bash
# etcd-maintenance.sh - Run weekly

ETCD_ENDPOINTS="http://etcd-observability-0:2379,http://etcd-observability-1:2379,http://etcd-observability-2:2379"

echo "=== etcd Status ==="
etcdctl --endpoints=$ETCD_ENDPOINTS endpoint status --write-out=table

echo ""
echo "=== Database Size ==="
etcdctl --endpoints=$ETCD_ENDPOINTS endpoint status --write-out=json | \
  jq -r '.[] | {endpoint: .Endpoint, dbSize: .Status.dbSize, dbSizeInUse: .Status.dbSizeInUse}'

echo ""
echo "=== Compact (if needed) ==="
REVISION=$(etcdctl --endpoints=$ETCD_ENDPOINTS endpoint status --write-out=json | \
  jq -r '.[0].Status.header.revision')
etcdctl --endpoints=$ETCD_ENDPOINTS compact $REVISION

echo ""
echo "=== Defragment (if needed) ==="
# WARNING: Causes brief unavailability
# etcdctl --endpoints=$ETCD_ENDPOINTS defrag --cluster
```

---

## Tier-Specific Observability Configurations

### XS Tier (1-10 Clusters)

| Component | CPU | Memory | Storage | Notes |
|-----------|-----|--------|---------|-------|
| Prometheus | 2 | 4 Gi | 50 Gi | Single instance, 7d retention |
| Loki | 1 | 2 Gi | 100 Gi | Single instance, 15d retention |
| Logging Operator | 500m | 1 Gi | - | Single instance |
| etcd (shared) | - | - | - | Use Kubernetes etcd |

**Total**: ~4 CPU, ~7 Gi memory, ~150 Gi storage

### S Tier (10-50 Clusters)

| Component | CPU | Memory | Storage | Notes |
|-----------|-----|--------|---------|-------|
| Prometheus | 4 | 8 Gi | 100 Gi | Single instance, 15d retention |
| Loki | 2 | 4 Gi | 200 Gi | Single instance, 30d retention |
| Logging Operator | 1 | 2 Gi | - | 2 replicas (HA) |
| etcd (shared) | - | - | - | Use Kubernetes etcd |

**Total**: ~8 CPU, ~14 Gi memory, ~300 Gi storage

### M Tier (50-200 Clusters)

| Component | CPU | Memory | Storage | Notes |
|-----------|-----|--------|---------|-------|
| Prometheus | 8 | 16 Gi | 200 Gi | Sharded (2 shards), 30d retention |
| Loki | 4 | 8 Gi | 500 Gi | Distributed mode, 30d retention |
| Logging Operator | 2 | 4 Gi | - | 3 replicas (HA) |
| etcd (optional) | 4 | 8 Gi | 100 Gi | Dedicated etcd (optional) |

**Total**: ~18 CPU, ~36 Gi memory, ~800 Gi storage

### L Tier (200-1,000 Clusters)

| Component | CPU | Memory | Storage | Notes |
|-----------|-----|--------|---------|-------|
| Prometheus + Sidecar | 24 | 48 Gi | 600 Gi | Sharded (3-4 shards), 30d retention |
| Thanos Query | 12 | 24 Gi | - | 3 replicas (HA) |
| Thanos Store | 8 | 16 Gi | 200 Gi | 2 replicas (caching) |
| Thanos Compactor | 4 | 8 Gi | 200 Gi | 1 instance |
| Loki | 8 | 16 Gi | 1 Ti | Distributed + object storage |
| Logging Operator | 4 | 8 Gi | - | 3 replicas + HPA |
| etcd (dedicated) | 8 | 16 Gi | 200 Gi | Dedicated etcd cluster (3 nodes) |

**Total**: ~68 CPU, ~136 Gi memory, ~2.4 Ti storage

### XL+ Tier (1,000+ Clusters)

| Component | Architecture | Notes |
|-----------|--------------|-------|
| Prometheus + Sidecar | 5+ shards per region | 30d retention, uploads to object storage |
| Thanos Query | 5+ replicas per region | Global federation |
| Thanos Store | 3+ replicas per region | Regional caching |
| Thanos Compactor | 2 instances (global) | Multi-region compaction |
| Thanos Ruler | 2+ replicas per region | Recording & alerting rules |
| Loki | Distributed + object storage | Multi-region |
| Logging Operator | Multiple instances per region | Regional aggregation |
| etcd | External etcd cluster | 5-7 nodes, high-performance |

**Total**: Distributed across multiple management clusters and regions

---

## Implementation Checklist for Observability Stack

### Phase 1: Baseline (XS-S Tier)

- [ ] **Deploy single Prometheus** with memory-optimized config
- [ ] **Deploy single Loki** with retention limits
- [ ] **Deploy logging operator** (Fluent Bit)
- [ ] **Set resource requests/limits** for all components
- [ ] **Configure retention policies** (7-15d)
- [ ] **Enable WAL compression** (Prometheus)
- [ ] **Monitor memory usage** (set up alerts)

### Phase 2: Optimization (S-M Tier)

- [ ] **Enable Prometheus sharding** (2-3 shards)
- [ ] **Switch Loki to distributed mode**
- [ ] **Optimize Fluent Bit buffers**
- [ ] **Increase retention** (30d)
- [ ] **Use object storage** for Loki (if available)
- [ ] **Scale logging operator** (2-3 replicas)

### Phase 3: Advanced (M-L Tier)

- [ ] **Deploy Thanos Sidecar** with Prometheus
- [ ] **Configure object storage** (S3/GCS/Nutanix Objects)
- [ ] **Deploy Thanos Query** for federation
- [ ] **Verify block uploads** to object storage
- [ ] **Reduce Prometheus retention** (30d)
- [ ] **Use object storage** for both Prometheus (via Thanos) and Loki
- [ ] **Deploy dedicated etcd** for observability (optional)
- [ ] **Implement query frontend** (Loki)
- [ ] **Enable HPA** for queriers
- [ ] **Set up federated querying** (multi-cluster)

### Phase 4: Enterprise Scale (L-XL+ Tier)

- [ ] **Deploy complete Thanos stack** (Query, Store, Compactor, Ruler)
- [ ] **Configure Thanos downsampling** (5m, 1h resolutions)
- [ ] **Set retention policies** (raw: 30d, 5m: 90d, 1h: 365d)
- [ ] **Multi-region deployment**
- [ ] **Centralized observability** (Thanos Query federation, Loki Query Frontend)
- [ ] **Object storage** (S3, GCS, Nutanix Objects)
- [ ] **Dedicated etcd clusters** per region
- [ ] **Automated retention policies**
- [ ] **Cost optimization** (compression, downsampling, object storage lifecycle)
- [ ] **Monitor Thanos components** (Store cache, Compactor lag, Query latency)

---

## References

### Prometheus

- [Prometheus Memory Usage](https://prometheus.io/docs/prometheus/latest/storage/)
- [Prometheus Sharding](https://prometheus.io/docs/prometheus/latest/storage/#operational-aspects)
- [Thanos Documentation](https://thanos.io/)

### Loki

- [Loki Architecture](https://grafana.com/docs/loki/latest/fundamentals/architecture/)
- [Loki Scalability](https://grafana.com/docs/loki/latest/operations/scalability/)
- [Loki Storage](https://grafana.com/docs/loki/latest/operations/storage/)

### Logging

- [Fluent Bit Memory Optimization](https://docs.fluentbit.io/manual/administration/memory-limits)
- [Logging Operator](https://banzaicloud.com/docs/one-eye/logging-operator/)

### etcd

- [etcd Performance Tuning](https://etcd.io/docs/v3.5/op-guide/performance/)
- [etcd Hardware Recommendations](https://etcd.io/docs/v3.5/op-guide/hardware/)

---

## Implementation Checklist

### Phase 1: Foundation (Week 1)

- [ ] **Set resource requests/limits** for all CAPI controllers
- [ ] **Set resource requests/limits** for all platform applications
- [ ] **Create resource quotas** for each namespace (XS/S/M/L tier)
- [ ] **Create limit ranges** for automatic resource assignment
- [ ] **Deploy monitoring stack** (Prometheus, Grafana)
- [ ] **Deploy logging stack** (Loki, logging operator)
- [ ] **Configure basic alerts** (CPU, memory, etcd size)
- [ ] **Set observability resource limits** (see Observability Stack Scaling section)

### Phase 2: Optimization (Week 2)

- [ ] **Configure bin packing** scheduler strategy
- [ ] **Verify pod distribution** (should be concentrated)
- [ ] **Create dedicated node pool** for platform services (or use anti-affinity)
- [ ] **Apply taints/tolerations** for platform nodes
- [ ] **Update CAPI QPS settings** based on tier
- [ ] **Increase controller concurrency** based on tier

### Phase 3: Advanced Tuning (Week 3)

- [ ] **Enable etcd auto-compaction**
- [ ] **Increase etcd quota** if needed
- [ ] **Configure API Priority and Fairness** for CAPI
- [ ] **Increase controller sync period** (reduce periodic load)
- [ ] **Implement HPA** for controllers (if needed)
- [ ] **Create comprehensive Grafana dashboards**
- [ ] **Optimize Prometheus memory** (WAL compression, retention limits)
- [ ] **Optimize Loki memory** (distributed mode, object storage)
- [ ] **Scale observability stack** based on tier (see Observability Stack Scaling section)

### Phase 4: Scale Testing (Week 4)

- [ ] **Create test clusters** in batches
- [ ] **Monitor metrics** during scale-up
- [ ] **Document bottlenecks** and breaking points
- [ ] **Adjust configurations** based on findings
- [ ] **Test failover scenarios** (node failures, controller restarts)

### Phase 5: Production Hardening (Week 5+)

- [ ] **Implement Pod Disruption Budgets**
- [ ] **Configure node autoscaling** (if applicable)
- [ ] **Set up log aggregation** (Loki, EFK)
- [ ] **Create runbooks** for common issues
- [ ] **Document operational procedures**
- [ ] **Plan for next tier** (if scaling beyond current tier)

---

## References

### Official Documentation

- [Kubernetes Resource Bin Packing](https://kubernetes.io/docs/concepts/scheduling-eviction/resource-bin-packing/)
- [Kubernetes Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Kubernetes Limit Ranges](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Kubernetes Scheduler](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)
- [Cluster API Documentation](https://cluster-api.sigs.k8s.io/)
- [etcd Performance Tuning](https://etcd.io/docs/v3.5/op-guide/performance/)

### Related Guides in This Repository

- `../capi/CLUSTER-API-SCALING-DEEP-DIVE.md` - Deep dive into CAPI scaling
- `../capi/CAPI-SCALING-SOLUTIONS-AND-FIXES.md` - Known fixes and solutions
- `../nkp/NKP-CAPI-ADVANCED-SCALING-GUIDE.md` - NKP-specific scaling guide
- `../bin-packing/K8s-Resource-Bin-Packing-Guide.md` - Detailed bin packing guide

### Case Studies

- [Metal³ Scaling to 1000 Clusters](https://metal3.io/blog/2024/05/30/Scaling_part_3.html)
- [PayPal: Scaling to 4K Nodes and 200K Pods](https://medium.com/paypal-tech/scaling-kubernetes-to-over-4k-nodes-and-200k-pods-29988fad6ed)
- [CNCF: Support for 100 Large-Scale Clusters](https://www.cncf.io/blog/2022/11/29/support-for-100-large-scale-clusters/)

---

*Document generated: January 2026*
