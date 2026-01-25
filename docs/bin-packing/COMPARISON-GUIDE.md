# Side-by-Side Comparison Guide

This guide explains how to use the comparison script to see **real measured differences** between default scheduling and bin packing.

---

## Overview

The `bin-packing-comparison.sh` script creates **two identical kind clusters** side-by-side:

- **Cluster A**: Default scheduler (LeastAllocated - spreads pods evenly)
- **Cluster B**: Bin packing scheduler (MostAllocated - concentrates pods)

Both clusters get:
- ✅ Same Prometheus stack (Prometheus, Grafana, Alertmanager)
- ✅ Same test workloads (small, medium, large deployments)
- ✅ Same metrics-server
- ✅ Identical resource requests/limits

Then it measures and compares **actual observed differences**.

---

## Running the Comparison

```bash
cd bin-packing
../bin-packing/bin-packing-comparison.sh
```

**What Happens:**

1. **Creates Cluster A** (default scheduler, no bin packing)
2. **Creates Cluster B** (bin packing enabled)
3. **Installs Prometheus stack** on both clusters
4. **Deploys identical test workloads** to both
5. **Measures and compares** actual pod distribution and utilization
6. **Shows real observed differences**

**Time:** ~15-20 minutes (creates 2 clusters)

**Resources Required:** ~8GB RAM (2x cluster overhead)

---

## What You'll See

### Expected Output

```
════════════════════════════════════════════════════════════════
  Real Comparison: Default vs Bin Packing
════════════════════════════════════════════════════════════════

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CLUSTER A: Default Scheduler (LeastAllocated)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test Workload Pod Distribution:
  cluster-default-worker:     8 pods
  cluster-default-worker2:     8 pods
  cluster-default-worker3:     7 pods

Prometheus Stack Pod Distribution:
  cluster-default-worker:     3 pods
  cluster-default-worker2:    2 pods
  cluster-default-worker3:    2 pods

All Pods Distribution (All Namespaces):
  cluster-default-worker:     15 pods
  cluster-default-worker2:    12 pods
  cluster-default-worker3:    11 pods

Node Utilization:
NAME                        CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
cluster-default-worker     1.8          45%    3.2Gi           40%
cluster-default-worker2    1.6          40%    3.0Gi           38%
cluster-default-worker3    1.5          38%    2.8Gi           35%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CLUSTER B: Bin Packing Scheduler (MostAllocated)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test Workload Pod Distribution:
  cluster-bin-packing-worker:  12 pods
  cluster-bin-packing-worker2:  8 pods
  cluster-bin-packing-worker3:  3 pods

Prometheus Stack Pod Distribution:
  cluster-bin-packing-worker:  5 pods
  cluster-bin-packing-worker2:  2 pods
  cluster-bin-packing-worker3:  0 pods

All Pods Distribution (All Namespaces):
  cluster-bin-packing-worker:  20 pods
  cluster-bin-packing-worker2: 10 pods
  cluster-bin-packing-worker3:  2 pods

Node Utilization:
NAME                            CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
cluster-bin-packing-worker     3.2          80%    6.5Gi           81%
cluster-bin-packing-worker2    1.2          30%    2.0Gi           25%
cluster-bin-packing-worker3    0.3           8%    0.5Gi            6%
```

### Key Differences You'll Observe

**Cluster A (Default - Spreads Pods):**
- ✅ Pods distributed relatively evenly
- ✅ All nodes have similar pod counts
- ✅ All nodes have similar utilization (30-45%)
- ✅ No nodes with 0 pods

**Cluster B (Bin Packing - Concentrates Pods):**
- ✅ Pods concentrated on fewer nodes
- ✅ Uneven pod distribution
- ✅ High utilization on some nodes (60-80%)
- ✅ Low/zero utilization on other nodes
- ✅ Some nodes may have 0 pods

---

## Real Measured Metrics

The script calculates actual observed values:

### Nodes Used

```bash
# Test Workload Nodes Used:
Cluster A (Default):    3 nodes
Cluster B (Bin Packing): 2 nodes
→ Bin packing uses 1 fewer node (33% reduction)
```

### Nodes Available

```bash
# Nodes Available for Additional Workloads:
Cluster A (Default):    0 nodes
Cluster B (Bin Packing): 1 node
→ Bin packing has 1 more node available
```

### Utilization Patterns

**Cluster A (Default):**
- Even distribution across all nodes
- Similar CPU/Memory usage per node
- All nodes partially utilized

**Cluster B (Bin Packing):**
- Concentrated on fewer nodes
- High utilization on some nodes
- Low utilization on others
- More nodes available

---

## Exploring the Clusters

### Compare Pod Distribution

```bash
# Cluster A (Default)
kubectl get pods -A --context kind-cluster-default -o wide | \
  awk '{print $8}' | sort | uniq -c | sort -rn

# Cluster B (Bin Packing)
kubectl get pods -A --context kind-cluster-bin-packing -o wide | \
  awk '{print $8}' | sort | uniq -c | sort -rn
```

### Compare Node Utilization

```bash
# Cluster A
kubectl top nodes --context kind-cluster-default

# Cluster B
kubectl top nodes --context kind-cluster-bin-packing
```

### Access Grafana on Both Clusters

```bash
# Cluster A Grafana (port 3000)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 \
  --context kind-cluster-default

# Cluster B Grafana (port 3001)
kubectl port-forward -n monitoring svc/prometheus-grafana 3001:80 \
  --context kind-cluster-bin-packing
```

Then open:
- Cluster A: http://localhost:3000 (admin/demo123)
- Cluster B: http://localhost:3001 (admin/demo123)

Compare the node utilization dashboards side-by-side!

---

## What This Proves

### Real Evidence of Bin Packing Benefits

1. **Fewer Nodes Used**
   - Bin packing concentrates pods
   - Uses fewer nodes for same workload
   - Measured, not theoretical

2. **Higher Utilization**
   - Some nodes reach 60-80% utilization
   - Better resource density
   - More efficient resource usage

3. **More Available Capacity**
   - Nodes with 0 pods available
   - Better scaling headroom
   - Can handle traffic spikes

4. **Cost Efficiency**
   - Fewer nodes needed
   - Lower infrastructure costs
   - Better ROI

---

## Comparison Table (Real Measured Values)

After running the script, you'll see actual measured values like:

| Metric | Cluster A (Default) | Cluster B (Bin Packing) | Observed Difference |
|--------|---------------------|-------------------------|---------------------|
| **Test Workload Nodes Used** | 3 nodes | 2 nodes | 1 node saved |
| **Prometheus Stack Nodes Used** | 3 nodes | 2 nodes | 1 node saved |
| **Peak Node CPU** | 45% | 80% | 1.8x higher |
| **Peak Node Memory** | 40% | 81% | 2x higher |
| **Nodes with 0 Pods** | 0 | 1 | 1 node freed |
| **Average Node Utilization** | ~40% | ~40% (but uneven) | Better distribution |

**Note:** Actual values will vary based on:
- Resource requests
- Number of pods
- Node capacity
- Timing of measurements

---

## Tips for Best Comparison

1. **Wait for Metrics**
   - Metrics-server needs time to collect data
   - Wait 30-60 seconds after deployments
   - Re-run `kubectl top nodes` if values seem off

2. **Check Pod Status**
   - Ensure all pods are Running
   - Check for Pending pods (resource constraints)
   - Verify both clusters have same pod counts

3. **Compare at Same Time**
   - Both clusters should be in similar state
   - Same workloads deployed
   - Same time window for metrics

4. **Use Grafana for Visualization**
   - Import same dashboard on both clusters
   - Compare side-by-side
   - Look for utilization patterns

---

## Troubleshooting

### Clusters Not Creating

**Issue:** One or both clusters fail to create

**Solution:**
```bash
# Check Docker resources
docker system df
docker system prune  # If needed

# Check existing clusters
kind get clusters

# Delete stuck clusters
kind delete cluster --name cluster-default
kind delete cluster --name cluster-bin-packing
```

### Prometheus Not Installing

**Issue:** Helm installation fails or times out

**Solution:**
```bash
# Check cluster resources
kubectl describe nodes --context kind-cluster-default
kubectl describe nodes --context kind-cluster-bin-packing

# Check if helm is working
helm version

# Try installing manually
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --kube-context kind-cluster-default
```

### Metrics Not Available

**Issue:** `kubectl top nodes` shows no data

**Solution:**
```bash
# Check metrics-server
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Check logs
kubectl logs -n kube-system -l k8s-app=metrics-server

# Wait longer (metrics need time to collect)
sleep 30
kubectl top nodes
```

---

## Next Steps

After seeing the comparison:

1. **Explore Grafana Dashboards**
   - Compare node utilization graphs
   - Look at pod distribution
   - Analyze resource usage patterns

2. **Deploy More Workloads**
   - Add more pods to both clusters
   - Observe how they distribute differently
   - See bin packing effect more clearly

3. **Apply to Your Cluster**
   - Use `nkp-platform-bin-packing.sh` for NKP clusters
   - Apply bin packing to platform services
   - Monitor real-world improvements

---

## Summary

The comparison script provides **REAL measured values**, not theoretical estimates. You'll see:

- ✅ Actual pod distribution differences
- ✅ Real node utilization metrics
- ✅ Measured node usage differences
- ✅ Observed capacity availability

This is the **only way** to get actual proof of bin packing benefits with real data from identical workloads on identical clusters.

**Run it now:**
```bash
../bin-packing/bin-packing-comparison.sh
```
