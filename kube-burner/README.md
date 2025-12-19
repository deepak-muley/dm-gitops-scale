# kube-burner Scale Testing

kube-burner is excellent for creating large numbers of Kubernetes objects quickly. It's optimized for high-throughput object creation.

## Prerequisites

Install `kube-burner`:

```bash
# macOS
brew install kube-burner

# Linux
wget https://github.com/cloud-bulldozer/kube-burner/releases/latest/download/kube-burner-linux-x86_64.tar.gz
tar -xzf kube-burner-linux-x86_64.tar.gz
sudo mv kube-burner /usr/local/bin/
```

## Usage

### Unified Command (Recommended)

Use the `kube-burner-cluster` command for all operations:

```bash
# Create clusters
./kube-burner-cluster create              # Create 10 clusters (default)
./kube-burner-cluster create 100          # Create 100 clusters
./kube-burner-cluster create 50 my-ns     # Create 50 in custom namespace
QPS=100 BURST=200 ./kube-burner-cluster create 1000

# Verify clusters
./kube-burner-cluster verify
./kube-burner-cluster verify my-namespace

# List clusters
./kube-burner-cluster list
./kube-burner-cluster list my-namespace

# Cleanup
./kube-burner-cluster cleanup
./kube-burner-cluster cleanup my-namespace

# Help
./kube-burner-cluster help
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

## Configuration

You can adjust the QPS (queries per second) and burst to control API server load:

```bash
# Lower QPS for slower API servers
QPS=20 BURST=40 ./create-clusters.sh 1000

# Higher QPS for faster API servers
QPS=100 BURST=200 ./create-clusters.sh 1000
```

## Resources

- **Best for**: High-throughput object creation, load testing
- **Documentation**: https://kube-burner.github.io/kube-burner/
- **Note**: kube-burner is optimized for creating many objects quickly

## Template Customization

You can customize the cluster template in `templates/cluster.yaml` to match your specific Cluster API configuration.

