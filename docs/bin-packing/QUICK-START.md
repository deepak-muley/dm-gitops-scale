# Quick Start Guide

Get started with Kubernetes resource bin packing in minutes!

---

## Option 0: Side-by-Side Comparison ⭐ **Best for Real Proof**

**Best for:** Seeing **actual measured differences** with identical applications

**Best for:** Seeing real measured differences between default and bin packing

```bash
cd bin-packing
../bin-packing/bin-packing-comparison.sh
```

**What you get:**
- ✅ Two clusters: one with default scheduler, one with bin packing
- ✅ **Identical Prometheus stack on both** (Prometheus, Grafana, Alertmanager)
- ✅ Identical test workloads deployed to both
- ✅ Real measured comparison of pod distribution
- ✅ Actual utilization metrics from both clusters
- ✅ **Observed differences (not theoretical)** - REAL proof!

**Time:** ~15-20 minutes (creates 2 clusters)

**Note:** Requires ~8GB RAM (2x cluster overhead)

## Option 1: Complete E2E Demonstration (Recommended)

**Best for:** Understanding bin packing with real metrics and visualizations

```bash
cd bin-packing
./bin-packing-e2e-demo.sh mostallocated
```

**What you get:**
- ✅ Kind cluster with bin packing enabled
- ✅ Prometheus, Grafana, Alertmanager installed
- ✅ Test workloads deployed
- ✅ Detailed utilization metrics
- ✅ Explanation of improvements
- ✅ Access to Grafana dashboards

**Time:** ~10-15 minutes

---

## Option 2: Basic Setup

**Best for:** Quick test or custom configuration

```bash
cd bin-packing
../bin-packing/bin-packing-kind-setup.sh mostallocated
```

When prompted, answer:
- `y` to install Prometheus stack
- `n` to skip (install manually later)

**What you get:**
- ✅ Kind cluster with bin packing
- ✅ Metrics-server installed
- ✅ Test deployment (15 pods)
- ✅ Optional Prometheus stack

**Time:** ~5-10 minutes

---

## Option 2.5: Analyze Existing Cluster

**Best for:** Analyzing any existing cluster's metrics and distribution

```bash
cd bin-packing
../bin-packing/cluster-metrics-analyzer.sh [context]
```

**What you get:**
- ✅ Pod distribution analysis
- ✅ Node utilization metrics
- ✅ Resource allocation details
- ✅ Bin packing indicators
- ✅ **Comparison Highlights** section (easy to compare across runs)
- ✅ Works with any cluster (not just bin packing clusters)

**Examples:**
```bash
# Analyze kind cluster
../bin-packing/cluster-metrics-analyzer.sh kind-bin-packing-demo

# Analyze production cluster
../bin-packing/cluster-metrics-analyzer.sh my-production-cluster

# Current context
../bin-packing/cluster-metrics-analyzer.sh
```

**Time:** ~10-30 seconds (depends on cluster size)

### Quick Side-by-Side Comparison

**Best for:** Comparing two clusters at once

```bash
cd bin-packing
../bin-packing/compare-clusters.sh <context1> <context2>
```

**Example:**
```bash
../bin-packing/compare-clusters.sh kind-cluster-default kind-cluster-bin-packing
```

**What you get:**
- ✅ Side-by-side metrics table
- ✅ Highlighted differences (✅ for improvements)
- ✅ Key takeaways
- ✅ Perfect for comparing default vs bin packing!

**Time:** ~20-60 seconds (depends on cluster sizes)

## Option 3: Apply to NKP Cluster

**Best for:** Production NKP management cluster

```bash
cd bin-packing

# Enable bin packing
./nkp-platform-bin-packing.sh enable

# Check status
./nkp-platform-bin-packing.sh status

# Test with sample deployment
./nkp-platform-bin-packing.sh test
```

**What you get:**
- ✅ Bin packing scheduler profile created
- ✅ Platform services can use bin packing
- ✅ Status and testing tools

**Time:** ~2-3 minutes

---

## What to Expect

### After Running E2E Demo

1. **Cluster Created**
   - 1 control plane + 3 worker nodes
   - Bin packing enabled on scheduler
   - Metrics-server running

2. **Prometheus Stack Installed**
   - Prometheus (metrics collection)
   - Grafana (visualization)
   - Alertmanager (alerting)
   - All pods concentrated on fewer nodes

3. **Test Workloads Deployed**
   - Multiple deployments with different resource sizes
   - Pods distributed showing bin packing effect

4. **Metrics Shown**
   - Node utilization (CPU/Memory)
   - Pod distribution per node
   - Resource allocation details
   - Utilization improvement explanation

5. **Access Information**
   - Grafana: http://localhost:3000 (admin/demo123)
   - Prometheus: http://localhost:9090
   - kubectl commands for exploration

### Key Observations

**With Bin Packing:**
- ✅ Pods concentrate on 2-3 nodes (not evenly spread)
- ✅ Some nodes have 0 pods (available for workloads)
- ✅ Higher utilization on nodes with pods (60-80%)
- ✅ Better resource density

**Without Bin Packing (for comparison):**
- ❌ Pods spread evenly across all nodes
- ❌ All nodes partially utilized (30-40%)
- ❌ No nodes available
- ❌ Lower resource density

---

## Next Steps

### Explore the Cluster

```bash
# Set context
kubectl config use-context kind-bin-packing-demo

# View all pods
kubectl get pods -A -o wide

# Check pod distribution (with -A, node is column 8)
kubectl get pods -A -o wide | awk '{print $8}' | sort | uniq -c | sort -rn

# View node metrics
kubectl top nodes

# View pod metrics
kubectl top pods -A
```

### Access Grafana

```bash
# Port forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open browser: http://localhost:3000
# Login: admin / demo123
```

**Recommended Dashboards:**
- Kubernetes Cluster Monitoring (ID: 6417)
- Node Exporter Full (ID: 1860)
- Create custom dashboard showing:
  - Node CPU/Memory utilization
  - Pod distribution per node
  - Resource requests vs usage

### Access Prometheus

```bash
# Port forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Open browser: http://localhost:9090
```

**Useful Queries:**
- `sum(rate(container_cpu_usage_seconds_total[5m])) by (node)` - CPU usage per node
- `sum(container_memory_working_set_bytes) by (node)` - Memory usage per node
- `count(kube_pod_info) by (node)` - Pod count per node

---

## Understanding the Results

### Pod Distribution Pattern

**Expected with Bin Packing:**
```
Node 1: 15 pods (70% CPU, 75% Memory) ← High utilization
Node 2: 12 pods (65% CPU, 70% Memory) ← High utilization
Node 3:  8 pods (45% CPU, 50% Memory) ← Medium utilization
Node 4:  0 pods ( 0% CPU,  0% Memory) ← Available!
```

**This shows:**
- ✅ Bin packing is working (uneven distribution)
- ✅ High utilization on some nodes
- ✅ Nodes available for scaling

### Utilization Metrics

**Check these metrics:**
1. **Node CPU Utilization:** Should see 60-80% on nodes with pods
2. **Node Memory Utilization:** Should see 60-80% on nodes with pods
3. **Pod Count per Node:** Should be uneven (not all equal)
4. **Available Nodes:** Some nodes should have 0 pods

---

## Troubleshooting

### Pods Still Spreading Evenly

**Possible causes:**
- Scheduler config not applied correctly
- Resource requests too large
- Node capacity constraints

**Check:**
```bash
# Verify scheduler config
kubectl logs -n kube-system -l component=kube-scheduler | grep -i "mostallocated\|bin"

# Check node capacity
kubectl describe nodes | grep -A 5 "Capacity:"

# Check resource requests
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources.requests}{"\n"}{end}'
```

### Metrics Not Available

**If `kubectl top` doesn't work:**
```bash
# Check metrics-server
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Check logs
kubectl logs -n kube-system -l k8s-app=metrics-server

# Restart if needed
kubectl rollout restart deployment/metrics-server -n kube-system
```

### Prometheus Not Starting

**If Prometheus pods are pending:**
```bash
# Check pod status
kubectl get pods -n monitoring

# Check events
kubectl describe pod -n monitoring -l app.kubernetes.io/name=prometheus

# Check resource constraints
kubectl describe nodes | grep -A 10 "Allocated resources"
```

---

## Cleanup

**To delete the cluster:**
```bash
kind delete cluster --name bin-packing-demo
```

**To keep the cluster for further testing:**
- Just leave it running
- Use `kubectl config use-context kind-bin-packing-demo` to access it
- Delete when done: `kind delete cluster --name bin-packing-demo`

---

## Learn More

- **[Bin Packing Utilization Explained](./BIN-PACKING-UTILIZATION-EXPLAINED.md)** - Detailed explanation with examples
- **[What to Expect Guide](./WHAT-TO-EXPECT.md)** - Complete guide on what happens
- **[Kubernetes Resource Bin Packing Guide](./K8s-Resource-Bin-Packing-Guide.md)** - Full technical guide
- **[Troubleshooting Guide](./TROUBLESHOOTING.md)** - Common issues and solutions

---

**Ready to start? Run:**
```bash
./bin-packing-e2e-demo.sh mostallocated
```
