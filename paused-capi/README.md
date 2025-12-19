# Paused CAPI Cluster Objects

Create fake/mock Cluster objects without actual infrastructure provisioning. This is ideal for testing GitOps reconciliation, Flux, and ArgoCD.

## Prerequisites

- Kubernetes cluster with Cluster API installed
- `kubectl` configured to access the cluster

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

