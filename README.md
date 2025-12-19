# dm-gitops-scale

Scale testing tools for Cluster API (CAPI) and GitOps workflows. This repository provides simple scripts to simulate 1000+ clusters using various lightweight methods.

## Overview

This repository contains implementations of 5 different scale testing approaches, each optimized for different use cases:

| Method | Resources per "Cluster" | Best For | Folder |
|--------|------------------------|----------|--------|
| **KWOK** | ~36KB/node | Testing node scaling, scheduling | [`kwok/`](./kwok/) |
| **Paused CAPI Objects** | ~1KB/object | Testing GitOps, Flux reconciliation | [`paused-capi/`](./paused-capi/) |
| **vcluster** | ~128MB/cluster | Testing actual workloads in isolation | [`vcluster/`](./vcluster/) |
| **Kubemark** | ~50MB/node | API server load testing | [`kubemark/`](./kubemark/) |
| **kube-burner** | Variable | High-throughput object creation | [`kube-burner/`](./kube-burner/) |

## Quick Start

Each method has its own folder with a unified command script. To get started:

### 1. Choose a Method

- **Lightest weight**: Use `paused-capi/` for GitOps testing
- **Most realistic**: Use `kwok/` for node simulation
- **Functional clusters**: Use `vcluster/` for actual workloads
- **API load testing**: Use `kubemark/` for API server stress testing
- **Fast creation**: Use `kube-burner/` for high-throughput

### 2. Navigate to the Folder

```bash
cd kwok  # or paused-capi, vcluster, kubemark, kube-burner
```

### 3. Use the Unified Command

Each folder has a unified command script (e.g., `kwok-cluster`, `paused-capi-cluster`):

```bash
# Create 10 clusters (default)
./kwok-cluster create

# Create 100 clusters
./kwok-cluster create 100

# Verify clusters
./kwok-cluster verify

# List clusters
./kwok-cluster list

# Cleanup
./kwok-cluster cleanup
```

### 4. Available Commands

All cluster types support these commands:
- `create` - Create clusters
- `verify` - Verify cluster health and status
- `cleanup` - Delete clusters
- `list` - List all clusters
- `help` - Show help message

Some cluster types have additional commands:
- `kwok-cluster scale` - Scale nodes in a cluster
- `kubemark-cluster setup` - Initial setup (run once)
- `kubemark-cluster scale` - Scale hollow nodes

## Directory Structure

```
.
├── README.md                 # This file
├── docs/
│   └── SCALE-TESTING.md      # Detailed documentation
├── kwok/                     # KWOK implementation
│   ├── kwok-cluster          # Unified command script
│   └── README.md
├── paused-capi/              # Paused CAPI objects
│   ├── paused-capi-cluster   # Unified command script
│   └── README.md
├── vcluster/                 # Virtual clusters
│   ├── vcluster-cluster       # Unified command script
│   └── README.md
├── kubemark/                 # Kubemark hollow nodes
│   ├── kubemark-cluster      # Unified command script
│   └── README.md
└── kube-burner/              # kube-burner load testing
    ├── kube-burner-cluster   # Unified command script
    ├── templates/
    │   └── cluster.yaml
    └── README.md
```

**Note**: The old individual scripts (`create-clusters.sh`, `cleanup-clusters.sh`, etc.) are still available for backward compatibility, but the new unified command scripts (e.g., `kwok-cluster`, `paused-capi-cluster`) are the recommended way to use these tools.

## Usage Examples

### Example 1: Test GitOps with 100 Paused Clusters

```bash
cd paused-capi
./paused-capi-cluster create 100

# Verify clusters
./paused-capi-cluster verify

# Watch your GitOps controller reconcile
watch -n 1 "kubectl get clusters -n dm-dev-workspace -l simulation=true --no-headers | wc -l"

# Cleanup
./paused-capi-cluster cleanup
```

### Example 2: Simulate 1000 Clusters with KWOK

```bash
cd kwok
./kwok-cluster create 1000

# Verify all clusters
./kwok-cluster verify

# List clusters
./kwok-cluster list

# Verify specific cluster
./kwok-cluster verify kwok-cluster-0001

# Cleanup
./kwok-cluster cleanup
```

### Example 3: API Server Load Testing with Kubemark

```bash
cd kubemark
./kubemark-cluster setup      # One-time setup
./kubemark-cluster create 500

# Verify
./kubemark-cluster verify

# Scale to 1000 nodes
./kubemark-cluster scale 1000

# Monitor API server
kubectl top pods -n kube-system | grep apiserver

# Cleanup
./kubemark-cluster cleanup
```

## Prerequisites

Each method has different prerequisites. Check the README in each folder:

- **KWOK**: Requires `kwokctl` - see [kwok/README.md](./kwok/README.md)
- **Paused CAPI**: Requires Kubernetes cluster with CAPI installed
- **vcluster**: Requires `vcluster` CLI - see [vcluster/README.md](./vcluster/README.md)
- **Kubemark**: Requires Kubernetes cluster - see [kubemark/README.md](./kubemark/README.md)
- **kube-burner**: Requires `kube-burner` CLI - see [kube-burner/README.md](./kube-burner/README.md)

## Configuration

All unified command scripts accept parameters to customize behavior:

- **Count**: First parameter for `create` command (default: 10)
- **Namespace/Prefix**: Second parameter (varies by method)

Examples:
```bash
# Create 100 clusters in custom namespace
cd paused-capi
./paused-capi-cluster create 100 my-namespace

# Create 50 KWOK clusters with custom prefix
cd kwok
./kwok-cluster create 50 my-prefix

# Verify specific cluster
./kwok-cluster verify kwok-cluster-0001
```

## Best Practices

1. **Start Small**: Test with 10 clusters first, then scale up
2. **Monitor Resources**: Watch API server and etcd performance
3. **Use Batching**: Scripts automatically batch operations to avoid overwhelming the API server
4. **Cleanup**: Always cleanup between tests to avoid resource leaks

## Monitoring

### Watch Cluster Count

```bash
watch -n 1 "kubectl get clusters -n dm-dev-workspace -l simulation=true --no-headers | wc -l"
```

### Check API Server Health

```bash
kubectl get --raw /healthz
kubectl get --raw /readyz
```

### Monitor Resource Usage

```bash
kubectl top nodes
kubectl top pods -n dm-dev-workspace --sum
```

## Documentation

- **Detailed Guide**: See [docs/SCALE-TESTING.md](./docs/SCALE-TESTING.md) for comprehensive documentation
- **Method-Specific**: Each folder contains a README with method-specific instructions

## Troubleshooting

### API Server Throttling

If you encounter throttling errors, reduce batch sizes or add delays:

```bash
# For paused-capi
BATCH_SIZE=20 ./create-clusters.sh 1000

# For kube-burner
QPS=20 BURST=40 ./create-clusters.sh 1000
```

### Memory Pressure

Monitor node resources and reduce concurrent operations if needed.

### etcd Performance

Check etcd status and consider compaction if database size grows too large.

## Contributing

Feel free to submit issues or pull requests to improve these scripts.

## License

This repository is provided as-is for scale testing purposes.

## References

- [KWOK Documentation](https://kwok.sigs.k8s.io/)
- [vcluster Documentation](https://www.vcluster.com/docs)
- [Kubemark Guide](https://github.com/kubernetes/kubernetes/tree/master/test/kubemark)
- [kube-burner Documentation](https://kube-burner.github.io/kube-burner/)
- [Cluster API Book](https://cluster-api.sigs.k8s.io/)
