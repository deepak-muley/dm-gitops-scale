# Cluster Metrics Analyzer

A standalone utility script to analyze any Kubernetes cluster's metrics, pod distribution, and resource utilization.

---

## Overview

The `cluster-metrics-analyzer.sh` script provides comprehensive analysis of any Kubernetes cluster, showing:
- ✅ Pod distribution across nodes
- ✅ Node resource utilization (CPU/Memory)
- ✅ Resource allocation details
- ✅ Bin packing indicators
- ✅ Top resource consumers
- ✅ Summary statistics

**Works with any cluster** - not just the ones created by bin packing scripts!

---

## Usage

### Basic Usage (Current Context)

```bash
./cluster-metrics-analyzer.sh
```

Uses the current kubectl context.

### Specify Context

```bash
./cluster-metrics-analyzer.sh kind-bin-packing-demo
./cluster-metrics-analyzer.sh my-production-cluster
./cluster-metrics-analyzer.sh gke_my-project_us-central1_cluster-name
```

### Using KUBECONFIG

```bash
export KUBECONFIG=/path/to/kubeconfig
./cluster-metrics-analyzer.sh my-cluster-context
```

---

## What It Shows

### 1. Cluster Information
- Kubernetes version
- Node count
- Total pod count

### 2. Node Resource Utilization
- CPU and Memory usage per node
- Node capacity and allocatable resources
- Utilization percentages

### 3. Pod Distribution
- All pods across all namespaces
- Pods per node
- Distribution by namespace
- Identifies nodes with 0 pods

### 4. Resource Allocation Details
- Detailed allocation from `kubectl describe nodes`
- Shows requests vs capacity
- Identifies resource pressure

### 5. Bin Packing Analysis
- Distribution statistics (min/max/average pods per node)
- Bin packing indicators
- Scheduler configuration check
- Identifies if bin packing is likely enabled

### 6. Top Resource Consumers
- Top CPU-consuming pods
- Top Memory-consuming pods
- Helps identify resource hogs

### 7. Summary Report
- Key metrics at a glance
- Average utilization
- Nodes available for scaling

---

## Example Output

```
════════════════════════════════════════════════════════════════
  Kubernetes Cluster Metrics Analyzer
════════════════════════════════════════════════════════════════

Context: kind-bin-packing-demo

✓ Connected to cluster

════════════════════════════════════════════════════════════════
  Cluster Information
════════════════════════════════════════════════════════════════

Kubernetes Version: v1.35.0
Node Count: 4
Total Pods: 45

════════════════════════════════════════════════════════════════
  Node Resource Utilization
════════════════════════════════════════════════════════════════

NAME                        CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
bin-packing-demo-worker     3.2          80%    6.5Gi           81%
bin-packing-demo-worker2    1.2          30%    2.0Gi           25%
bin-packing-demo-worker3    0.3           8%    0.5Gi            6%

════════════════════════════════════════════════════════════════
  Pod Distribution Across Nodes
════════════════════════════════════════════════════════════════

All Pods (All Namespaces):

  bin-packing-demo-worker:     20 pods
  bin-packing-demo-worker2:    15 pods
  bin-packing-demo-worker3:     10 pods

By Namespace:

Namespace: default (23 pods)
    bin-packing-demo-worker:     12 pods
    bin-packing-demo-worker2:     8 pods
    bin-packing-demo-worker3:     3 pods

Namespace: monitoring (15 pods)
    bin-packing-demo-worker:     8 pods
    bin-packing-demo-worker2:   5 pods
    bin-packing-demo-worker3:   2 pods

════════════════════════════════════════════════════════════════
  Bin Packing Analysis
════════════════════════════════════════════════════════════════

Distribution Statistics:
  Total Nodes: 3
  Total Pods: 45
  Average Pods per Node: 15
  Min Pods per Node: 10
  Max Pods per Node: 20
  Nodes with 0 Pods: 0

  Distribution Ratio (Max/Min): 2.00

Bin Packing Indicators:
  ⚠️  All nodes have pods (may indicate default scheduler)
  ✅ High distribution variance (bin packing likely enabled)
     → Pods concentrated on fewer nodes

Scheduler Configuration Check:
  ✅ Bin packing scheduler detected in logs
     Scheduler appears to be using bin packing strategy
```

---

## Use Cases

### 1. Analyze Bin Packing Effectiveness

After enabling bin packing on your cluster:

```bash
./cluster-metrics-analyzer.sh my-nkp-cluster
```

Check if:
- Pods are concentrated on fewer nodes
- Some nodes have 0 pods
- High utilization variance

### 2. Compare Before/After

```bash
# Before enabling bin packing
./cluster-metrics-analyzer.sh my-cluster > before.txt

# Enable bin packing
./nkp-platform-bin-packing.sh enable

# After enabling bin packing
./cluster-metrics-analyzer.sh my-cluster > after.txt

# Compare
diff before.txt after.txt
```

### 3. Monitor Cluster Health

Regular monitoring:

```bash
# Add to cron or monitoring system
./cluster-metrics-analyzer.sh production-cluster >> metrics.log
```

### 4. Troubleshooting

When investigating resource issues:

```bash
./cluster-metrics-analyzer.sh problematic-cluster
```

Shows:
- Which nodes are overloaded
- Pod distribution issues
- Resource allocation problems

---

## Bin Packing Indicators

The script analyzes several indicators to determine if bin packing is likely enabled:

### Strong Indicators (Bin Packing Likely)
- ✅ Some nodes have 0 pods
- ✅ High distribution variance (max/min ratio > 2)
- ✅ Scheduler logs mention "MostAllocated" or "RequestedToCapacityRatio"
- ✅ Uneven pod distribution (some nodes with many pods, others with few)

### Weak Indicators (Default Scheduler Likely)
- ⚠️ All nodes have pods
- ⚠️ Low distribution variance (max/min ratio < 1.5)
- ⚠️ Relatively even pod distribution
- ⚠️ No bin packing mentions in scheduler logs

---

## Requirements

- `kubectl` installed and configured
- Access to the cluster (via context or kubeconfig)
- `jq` (optional, for JSON parsing - script works without it)
- `bc` (optional, for ratio calculations - script works without it)

**Note:** Metrics require metrics-server to be installed. The script will work without it but won't show utilization metrics.

---

## Examples

### Analyze Kind Cluster

```bash
./cluster-metrics-analyzer.sh kind-bin-packing-demo
```

### Analyze NKP Cluster

```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/config

# Analyze
./cluster-metrics-analyzer.sh my-nkp-cluster-context
```

### Analyze Remote Cluster

```bash
# Using kubeconfig file
export KUBECONFIG=/path/to/remote-kubeconfig
./cluster-metrics-analyzer.sh remote-cluster-context
```

### Save Output to File

```bash
./cluster-metrics-analyzer.sh my-cluster > cluster-analysis.txt
```

### Compare Two Clusters

```bash
# Cluster A
./cluster-metrics-analyzer.sh cluster-default > cluster-a.txt

# Cluster B
./cluster-metrics-analyzer.sh cluster-bin-packing > cluster-b.txt

# Compare
diff cluster-a.txt cluster-b.txt
```

---

## Integration with Comparison Script

After running the comparison script, analyze both clusters:

```bash
# Analyze Cluster A (default scheduler)
./cluster-metrics-analyzer.sh cluster-default > cluster-a-analysis.txt

# Analyze Cluster B (bin packing scheduler)
./cluster-metrics-analyzer.sh cluster-bin-packing > cluster-b-analysis.txt

# Compare the analyses
diff cluster-a-analysis.txt cluster-b-analysis.txt
```

---

## Troubleshooting

### Error: Cannot access cluster

**Solution:**
```bash
# List available contexts
kubectl config get-contexts

# Use correct context name
./cluster-metrics-analyzer.sh correct-context-name
```

### Metrics Not Available

**Solution:**
```bash
# Check if metrics-server is installed
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Install if missing (for kind clusters)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### No Pods Found

**Solution:**
- Check if cluster has any workloads
- Verify namespace permissions
- Check if pods are in different namespaces

---

## Advanced Usage

### Filter by Namespace

Modify the script or use kubectl directly:

```bash
# Get pod distribution for specific namespace
kubectl get pods -n monitoring --context my-cluster -o wide | \
  awk '{print $7}' | sort | uniq -c | sort -rn
```

### Export as JSON

```bash
# Get node metrics as JSON
kubectl top nodes --context my-cluster -o json

# Get pod distribution as JSON
kubectl get pods --all-namespaces --context my-cluster -o json | \
  jq '.items[] | {namespace: .metadata.namespace, node: .spec.nodeName}'
```

---

## Script Output Sections

1. **Cluster Information** - Basic cluster stats
2. **Node Resource Utilization** - CPU/Memory per node
3. **Pod Distribution** - How pods are spread across nodes
4. **Resource Allocation** - Detailed allocation from nodes
5. **Bin Packing Analysis** - Indicators and statistics
6. **Top Resource Consumers** - Resource-heavy pods
7. **Summary Report** - Key metrics at a glance

---

## Quick Comparison

For side-by-side comparison of two clusters, use the comparison script:

```bash
../bin-packing/compare-clusters.sh kind-cluster-default kind-cluster-bin-packing
```

This will show:
- ✅ Side-by-side metrics table
- ✅ Highlighted differences
- ✅ Key takeaways
- ✅ Easy-to-read comparison

## Related Scripts

- `compare-clusters.sh` - **Quick side-by-side comparison** of two clusters
- `../bin-packing/bin-packing-comparison.sh` - Creates two clusters and compares them
- `../bin-packing/bin-packing-e2e-demo.sh` - E2E demonstration with Prometheus
- `nkp-platform-bin-packing.sh` - Apply bin packing to NKP clusters

---

## Tips

1. **Run regularly** to track changes over time
2. **Save output** for historical comparison
3. **Use with comparison script** to see before/after
4. **Check bin packing indicators** to verify if enabled
5. **Monitor nodes with 0 pods** - indicates bin packing working

---

**Quick Start:**
```bash
./cluster-metrics-analyzer.sh your-cluster-context
```
