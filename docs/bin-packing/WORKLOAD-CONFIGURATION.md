# Test Workload Configuration

This document describes the test workloads deployed in the bin packing comparison clusters.

---

## Overview

The comparison scripts deploy three types of test workloads to demonstrate bin packing behavior:

1. **test-workload-small** - Lightweight pods
2. **test-workload-medium** - Medium-sized pods
3. **test-workload-large** - Large pods

---

## Workload Details

### 1. test-workload-small

**Configuration:**
- **Replicas:** 10 pods
- **Image:** nginx:latest
- **CPU Request:** 100m (0.1 cores)
- **CPU Limit:** 200m (0.2 cores)
- **Memory Request:** 128Mi
- **Memory Limit:** 256Mi

**Purpose:** Represents lightweight workloads that can be packed densely.

**Total Resource Requests (10 replicas):**
- CPU: 1000m (1 core)
- Memory: 1.28Gi

---

### 2. test-workload-medium

**Configuration:**
- **Replicas:** 8 pods
- **Image:** nginx:latest
- **CPU Request:** 200m (0.2 cores)
- **CPU Limit:** 500m (0.5 cores)
- **Memory Request:** 256Mi
- **Memory Limit:** 512Mi

**Purpose:** Represents medium-sized workloads with moderate resource requirements.

**Total Resource Requests (8 replicas):**
- CPU: 1600m (1.6 cores)
- Memory: 2.048Gi

---

### 3. test-workload-large

**Configuration:**
- **Replicas:** 5 pods
- **Image:** nginx:latest
- **CPU Request:** 500m (0.5 cores)
- **CPU Limit:** 1000m (1 core)
- **Memory Request:** 512Mi
- **Memory Limit:** 1Gi

**Purpose:** Represents resource-intensive workloads that require more space.

**Total Resource Requests (5 replicas):**
- CPU: 2500m (2.5 cores)
- Memory: 2.56Gi

---

## Total Test Workload Resources

**Combined Resource Requests (23 pods total):**
- **Total CPU:** 5100m (5.1 cores)
- **Total Memory:** ~5.9Gi

**Breakdown:**
- Small: 10 pods × 100m CPU = 1000m CPU
- Medium: 8 pods × 200m CPU = 1600m CPU
- Large: 5 pods × 500m CPU = 2500m CPU

---

## Additional Workloads

In addition to the test workloads, the clusters also include:

### Prometheus Stack
- **Chart:** kube-prometheus-stack
- **Components:**
  - Prometheus (metrics collection)
  - Grafana (visualization)
  - Alertmanager (alerting)
  - Node Exporter (node metrics)
  - Kube State Metrics (K8s metrics)
- **Typical Pod Count:** ~10-15 pods
- **Resource Usage:** Varies, typically 1-2 cores CPU, 2-4Gi memory

### Metrics-Server
- **Purpose:** Cluster resource metrics for `kubectl top`
- **Pod Count:** 1-2 pods
- **Resource Usage:** ~100m CPU, ~200Mi memory

### System Pods
- **Namespace:** kube-system
- **Components:**
  - CoreDNS
  - kube-proxy
  - etcd (control plane)
  - kube-apiserver (control plane)
  - kube-controller-manager (control plane)
  - kube-scheduler (control plane)
- **Typical Pod Count:** ~5-10 pods
- **Resource Usage:** Varies by cluster size

---

## Expected Pod Distribution

### Default Scheduler (LeastAllocated)
- **Behavior:** Spreads pods evenly across nodes
- **Expected:** Pods distributed relatively evenly
- **Result:** All nodes partially used, less room for new pods

### Bin Packing Scheduler (MostAllocated)
- **Behavior:** Concentrates pods on fewer nodes
- **Expected:** Pods packed densely on some nodes, others free
- **Result:** More pods can be scheduled, better utilization

---

## Workload YAML

The workloads are defined in the comparison script as:

```yaml
# test-workload-small
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-workload-small
spec:
  replicas: 10
  template:
    spec:
      containers:
      - name: app
        image: nginx:latest
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi

# test-workload-medium
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-workload-medium
spec:
  replicas: 8
  template:
    spec:
      containers:
      - name: app
        image: nginx:latest
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi

# test-workload-large
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-workload-large
spec:
  replicas: 5
  template:
    spec:
      containers:
      - name: app
        image: nginx:latest
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
```

---

## Checking Workload Status

### View All Test Workloads

```bash
# Cluster A
kubectl get pods --context kind-cluster-default -l 'app in (test-workload-small,test-workload-medium,test-workload-large)'

# Cluster B
kubectl get pods --context kind-cluster-bin-packing -l 'app in (test-workload-small,test-workload-medium,test-workload-large)'
```

### View by Workload Type

```bash
# Small workloads
kubectl get pods --context kind-cluster-default -l app=test-workload-small

# Medium workloads
kubectl get pods --context kind-cluster-default -l app=test-workload-medium

# Large workloads
kubectl get pods --context kind-cluster-default -l app=test-workload-large
```

### Check Deployment Status

```bash
# All test workload deployments
kubectl get deployments --context kind-cluster-default | grep test-workload

# Specific deployment
kubectl describe deployment test-workload-small --context kind-cluster-default
```

---

## Resource Calculations

### Per Node (Kind Cluster)
- **Typical Node Capacity:**
  - CPU: 4 cores (4000m)
  - Memory: 8Gi

### With Bin Packing
- **Expected:** 2-3 nodes heavily used (80-90%), 1-2 nodes free (0-10%)
- **Result:** More pods scheduled, better utilization

### Without Bin Packing (Default)
- **Expected:** All nodes partially used (50-70% each)
- **Result:** Less room for new pods, more pending

---

## Notes

- All test workloads use the same image (nginx:latest) for consistency
- Resource requests are what the scheduler uses for placement decisions
- Resource limits prevent pods from consuming more than allocated
- The mix of small/medium/large pods helps demonstrate bin packing effectiveness
- Prometheus stack adds significant additional workload (~10-15 pods)

---

## Modifying Workloads

To modify the workloads, edit the `deploy_workloads()` function in:
- `../bin-packing/bin-packing-comparison.sh`

Changes to consider:
- Number of replicas per workload
- CPU/Memory requests and limits
- Adding more workload types
- Using different container images

---

**See Also:**
- [Comparison Guide](./COMPARISON-GUIDE.md)
- [Bin Packing Explained](./BIN-PACKING-UTILIZATION-EXPLAINED.md)
- [Quick Start](./QUICK-START.md)
