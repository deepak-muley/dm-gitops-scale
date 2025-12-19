# vcluster Scale Testing

vcluster creates lightweight virtual clusters inside a host cluster - much less resource-intensive than real clusters, but still functional.

## Prerequisites

Install `vcluster`:

```bash
# macOS
brew install loft-sh/tap/vcluster

# Linux/Other
curl -L -o vcluster "https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64"
chmod +x vcluster
sudo mv vcluster /usr/local/bin/
```

## Usage

### Unified Command (Recommended)

Use the `vcluster-cluster` command for all operations:

```bash
# Create clusters
./vcluster-cluster create              # Create 10 clusters (default)
./vcluster-cluster create 100          # Create 100 clusters
./vcluster-cluster create 50 my-prefix # Create 50 with custom prefix

# Verify/list clusters
./vcluster-cluster verify
./vcluster-cluster list

# Cleanup
./vcluster-cluster cleanup
./vcluster-cluster cleanup my-prefix

# Help
./vcluster-cluster help
```

### Manual Commands

```bash
# List all virtual clusters
vcluster list

# Connect to a specific vcluster
vcluster connect vc-0001 -n vcluster-0001

# Check vcluster pods
kubectl get pods -n vcluster-0001
```

## Resources

- **Memory per cluster**: ~128MB/cluster
- **Best for**: Testing actual workloads in isolation
- **Documentation**: https://www.vcluster.com/docs

## Notes

- Each vcluster runs in its own namespace
- vclusters are functional Kubernetes clusters that can run workloads
- Much lighter than real clusters but heavier than KWOK or paused CAPI objects

