# Paused CAPI Cluster Objects

Create fake/mock Cluster objects without actual infrastructure provisioning. This is ideal for testing GitOps reconciliation, Flux, and ArgoCD.

## Prerequisites

- Kubernetes cluster with Cluster API installed
- `kubectl` configured to access the cluster

## How It Works

Paused CAPI clusters leverage Cluster API's built-in **pause mechanism** to create lightweight cluster representations without provisioning actual infrastructure.

### The Pause Mechanism

Cluster API supports a `paused` field in the `Cluster` spec and a `cluster.x-k8s.io/paused` annotation. When a cluster is marked as paused:

1. **CAPI Controllers Skip Reconciliation**: All Cluster API controllers (infrastructure providers, bootstrap providers, control plane providers) check for the `paused` flag before performing any reconciliation actions.

2. **No Infrastructure Provisioning**: Because controllers skip reconciliation, no actual infrastructure is created:
   - No VMs, instances, or compute resources
   - No network configuration
   - No load balancers
   - No actual Kubernetes control plane

3. **API Objects Only**: The `Cluster` object exists only as an API object in etcd, consuming minimal resources (~1KB per object).

### What Gets Created

When you create a paused cluster, only the following Kubernetes API objects are created:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: sim-cluster-0001
  annotations:
    cluster.x-k8s.io/paused: "true"  # Annotation for pause
  labels:
    simulation: "true"
spec:
  paused: true                        # Spec field for pause
  clusterNetwork:
    pods:
      cidrBlocks: ["10.0.0.0/24"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
```

**No infrastructure resources are created** - no `Machine` objects, no `MachineDeployment` objects, no actual infrastructure.

### Why This Is Useful

1. **GitOps Testing**: Test how your GitOps tools (Flux, ArgoCD) handle large numbers of cluster objects without waiting for provisioning.

2. **Reconciliation Testing**: Verify that controllers correctly handle paused clusters without attempting to reconcile them.

3. **Scale Testing**: Test API server and etcd performance with thousands of cluster objects without consuming compute resources.

4. **Quick Iteration**: Quickly test cluster naming, labeling, and organization strategies.

### Unpausing Clusters

To actually provision infrastructure for a paused cluster, remove the `paused` flag:

```bash
# Unpause a cluster to start provisioning
kubectl patch cluster sim-cluster-0001 -n dm-dev-workspace \
  --type=merge -p '{"spec":{"paused":false}}'
kubectl annotate cluster sim-cluster-0001 -n dm-dev-workspace \
  cluster.x-k8s.io/paused-

# CAPI controllers will now start reconciling and provisioning infrastructure
```

### Differences from Other Methods

| Method | What It Creates | Resource Usage | Use Case |
|--------|----------------|----------------|----------|
| **Paused CAPI** | API objects only | ~1KB/object | GitOps testing, reconciliation |
| **KWOK** | Simulated cluster + nodes | ~36KB/node | Node scheduling, scaling |
| **vcluster** | Lightweight virtual cluster | ~128MB/cluster | Workload isolation |
| **Kubemark** | Hollow nodes | ~50MB/node | API server load testing |

## Usage

### Unified Command (Recommended)

Use the `paused-capi-cluster` command for all operations:

```bash
# Create clusters
./paused-capi-cluster create              # Create 10 clusters (default)
./paused-capi-cluster create 100          # Create 100 clusters
./paused-capi-cluster create 50 my-ns      # Create 50 in custom namespace
BATCH_SIZE=20 ./paused-capi-cluster create 1000  # Custom batch size

# Verify clusters
./paused-capi-cluster verify
./paused-capi-cluster verify my-namespace

# List clusters
./paused-capi-cluster list
./paused-capi-cluster list my-namespace

# Cleanup
./paused-capi-cluster cleanup
./paused-capi-cluster cleanup my-namespace

# Help
./paused-capi-cluster help
```

### Manual Commands

```bash
# List all simulated clusters
kubectl get clusters -n dm-dev-workspace -l simulation=true

# Count clusters
kubectl get clusters -n dm-dev-workspace -l simulation=true --no-headers | wc -l

# Watch cluster creation
watch -n 1 "kubectl get clusters -n dm-dev-workspace -l simulation=true --no-headers | wc -l"
```

## Resources

- **Memory per cluster**: ~1KB/object
- **Best for**: Testing GitOps, Flux reconciliation, ArgoCD
- **Note**: These are paused Cluster objects that don't provision actual infrastructure

## Configuration

You can adjust the batch size to control API server load:

```bash
# Smaller batches for slower API servers
BATCH_SIZE=20 ./create-clusters.sh 1000

# Larger batches for faster API servers
BATCH_SIZE=100 ./create-clusters.sh 1000
```

