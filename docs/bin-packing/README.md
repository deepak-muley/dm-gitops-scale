# Kubernetes Resource Bin Packing

This directory contains scripts and examples for enabling and testing Kubernetes resource bin packing.

**🚀 Quick Start:** See [QUICK-START.md](./QUICK-START.md) to get started in minutes!

## Scripts

### `bin-packing-comparison.sh`

Creates TWO clusters side-by-side to compare default scheduler vs bin packing with REAL measurements.

**Usage:**
```bash
./bin-packing-comparison.sh
```

**What it does:**
1. Creates Cluster A with default scheduler (LeastAllocated - spreads pods)
2. Creates Cluster B with bin packing scheduler (MostAllocated - concentrates pods)
3. Deploys identical workloads to both
4. Measures and compares actual utilization
5. Shows real observed differences

**Note:** Requires more resources (~8GB RAM) as it creates 2 clusters.

### `bin-packing-kind-setup.sh`

Sets up a kind cluster with Kubernetes resource bin packing enabled. Demonstrates both `MostAllocated` and `RequestedToCapacityRatio` strategies.

**Usage:**
```bash
../bin-packing/bin-packing-kind-setup.sh [strategy]
```

**Strategies:**
- `mostallocated` (default) - Simple bin packing favoring nodes with highest utilization
- `requestedtocapacityratio` - Customizable bin packing with configurable scoring function

**Example:**
```bash
# Use MostAllocated strategy
../bin-packing/bin-packing-kind-setup.sh mostallocated

# Use RequestedToCapacityRatio strategy
../bin-packing/bin-packing-kind-setup.sh requestedtocapacityratio
```

**What it does:**
1. Creates a kind cluster with 1 control-plane and 3 worker nodes
2. Configures kube-scheduler with bin packing strategy
3. Creates a test deployment with 15 replicas
4. Shows pod distribution across nodes to demonstrate bin packing behavior
5. **Cluster remains running** after script completes (not automatically deleted)

### `cluster-metrics-analyzer.sh` 🔍 **Standalone Analysis Tool**

Analyzes **any Kubernetes cluster** to show metrics, pod distribution, and resource utilization.

**Usage:**
```bash
./cluster-metrics-analyzer.sh [context]
```

**What it shows:**
- Pod distribution across nodes
- Node CPU/Memory utilization
- Resource allocation details
- Bin packing indicators
- Top resource consumers
- Summary statistics

**Works with any cluster** - not just bin packing clusters!

**Examples:**
```bash
# Current context
./cluster-metrics-analyzer.sh

# Specific context
./cluster-metrics-analyzer.sh kind-bin-packing-demo
./cluster-metrics-analyzer.sh my-production-cluster

# With kubeconfig
export KUBECONFIG=/path/to/kubeconfig
./cluster-metrics-analyzer.sh cluster-context
```

**See [cluster-metrics-analyzer-README.md](./cluster-metrics-analyzer-README.md) for details.**

**Script location:** `../bin-packing/cluster-metrics-analyzer.sh`

### `compare-clusters.sh` 🔄 **Quick Side-by-Side Comparison**

Compares two clusters side-by-side with highlighted differences.

**Usage:**
```bash
../bin-packing/compare-clusters.sh <context1> <context2>
```

**Examples:**
```bash
../bin-packing/compare-clusters.sh kind-cluster-default kind-cluster-bin-packing
../bin-packing/compare-clusters.sh production-cluster staging-cluster
```

**What it shows:**
- Side-by-side metrics table
- Highlighted differences (✅ for improvements)
- Key takeaways
- Easy-to-read comparison format

**Perfect for:** Quickly comparing default vs bin packing clusters!

### `diagnose-unscheduled-pods.sh` 🔍 **Pod Scheduling Diagnosis**

Identifies which pods could not be scheduled and why.

**Usage:**
```bash
../bin-packing/diagnose-unscheduled-pods.sh <context>
```

**Examples:**
```bash
../bin-packing/diagnose-unscheduled-pods.sh kind-cluster-default
../bin-packing/diagnose-unscheduled-pods.sh kind-cluster-bin-packing
```

**What it shows:**
- Pending pods and their scheduling reasons
- Deployments with missing replicas
- ReplicaSet status (detailed pod creation)
- Recent scheduling events
- Node resource availability
- Summary of unscheduled pods

**Perfect for:** Finding out why pods couldn't be scheduled!

### `nkp-platform-bin-packing.sh`

Applies resource bin packing configuration to Nutanix NKP platform services.

**Usage:**
```bash
./nkp-platform-bin-packing.sh [action]
```

**Actions:**
- `enable` - Enable bin packing for platform services
- `disable` - Disable bin packing (restore default)
- `status` - Show current bin packing status
- `test` - Test bin packing with sample deployment

**Example:**
```bash
# Enable bin packing
./nkp-platform-bin-packing.sh enable

# Check status
./nkp-platform-bin-packing.sh status

# Test with sample deployment
./nkp-platform-bin-packing.sh test
```

## Prerequisites

### For kind cluster setup:
- [kind](https://kind.sigs.k8s.io/) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- Docker running
- Sufficient system resources (at least 4GB RAM free)

### For NKP platform bin packing:
- kubectl configured to access NKP management cluster
- Cluster admin permissions
- Access to kube-system namespace

## Frequently Asked Questions

See [FAQ.md](./FAQ.md) for common questions including:
- Do I need to delete clusters before running comparison?
- Resource requirements
- Understanding results
- Troubleshooting tips

## Troubleshooting

### Script hangs on `kind get clusters`

If the script hangs when checking for existing clusters:
- Check if Docker is running: `docker ps`
- Check if kind is working: `kind get clusters`
- The script now includes a timeout to prevent hanging

### Permission errors with kubeconfig

If you see permission errors:
```bash
# Fix kubeconfig permissions
chmod 600 ~/.kube/config

# Remove lock file if stuck
rm -f ~/.kube/config.lock
```

### Cluster creation fails

If kind cluster creation fails:
- Ensure Docker has enough resources allocated
- Check Docker logs: `docker logs <container-name>`
- Try deleting existing cluster: `kind delete cluster --name bin-packing-demo`

## Comparison Scripts

### `bin-packing-comparison.sh` ⭐ **Best for Real Measurements**

Creates TWO clusters side-by-side to compare default scheduler vs bin packing with **REAL measured values**.

**Usage:**
```bash
./bin-packing-comparison.sh
```

**What it does:**
- Creates Cluster A: Default scheduler (spreads pods)
- Creates Cluster B: Bin packing scheduler (concentrates pods)
- **Installs identical Prometheus stack on both** (Prometheus, Grafana, Alertmanager)
- Deploys identical test workloads to both
- Measures actual utilization differences
- Shows **real observed** metrics (not theoretical)

**This is the only way to get actual measured comparison with real applications!**

**See [COMPARISON-GUIDE.md](./COMPARISON-GUIDE.md) for detailed explanation.**

### `bin-packing-e2e-demo.sh`

Complete end-to-end demonstration that:
- Creates cluster with bin packing
- Installs kube-prometheus-stack (Prometheus, Grafana, Alertmanager)
- Deploys test workloads
- Shows utilization improvements with detailed metrics
- Explains how bin packing increases utilization

**Usage:**
```bash
./bin-packing-e2e-demo.sh [strategy]
```

**What it shows:**
- Pod distribution (concentrated)
- Node utilization metrics
- Resource allocation details
- Comparison with theoretical "without bin packing" values
- Access to Grafana/Prometheus for visualization

**Note:** The "Without Bin Packing" comparison values are **theoretical** based on expected default scheduler behavior. For real measurements, use `bin-packing-comparison.sh`.

See [Bin Packing Utilization Explained](./BIN-PACKING-UTILIZATION-EXPLAINED.md) for detailed explanation.

## Related Documentation

- **[What to Expect Guide](./WHAT-TO-EXPECT.md)** - Detailed explanation of what happens when you run the scripts and what results to expect
- **[Bin Packing Utilization Explained](./BIN-PACKING-UTILIZATION-EXPLAINED.md)** - How bin packing improves utilization with examples and metrics
- [Kubernetes Resource Bin Packing Guide](./K8s-Resource-Bin-Packing-Guide.md) - Complete guide with explanations and examples
- [NKP Platform Applications Guide](../docs/nkp/NKP-Platform-Applications-Guide.md) - NKP platform services overview
- [Troubleshooting Guide](./TROUBLESHOOTING.md) - Common issues and solutions

## Expected Behavior

### With Bin Packing (MostAllocated):
- Pods concentrate on fewer nodes
- Higher node utilization (60-80%)
- Fewer nodes used overall

### Without Bin Packing (Default):
- Pods spread evenly across nodes
- Lower node utilization (30-40%)
- More nodes used

**For detailed expectations and examples, see [WHAT-TO-EXPECT.md](./WHAT-TO-EXPECT.md)**

## Example Output

When running the script successfully, you should see:

```
Pod count per node:
   5 bin-packing-demo-worker2
   5 bin-packing-demo-worker3
   5 bin-packing-demo-worker
```

This shows pods are concentrated on fewer nodes (bin packing working).
