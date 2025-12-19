# KWOK Scale Testing

KWOK (Kubernetes Without Kubelet) is the most resource-efficient option - it can simulate 1000s of nodes using only ~36MB memory per 1000 nodes!

## Prerequisites

Install `kwokctl`:

```bash
# macOS
brew install kwok

# Or via go install
go install sigs.k8s.io/kwok/cmd/kwok@latest
go install sigs.k8s.io/kwok/cmd/kwokctl@latest

# Linux
KWOK_REPO=kubernetes-sigs/kwok
KWOK_LATEST_RELEASE=$(curl "https://api.github.com/repos/${KWOK_REPO}/releases/latest" | jq -r '.tag_name')
wget -O kwokctl "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/kwokctl-$(go env GOOS)-$(go env GOARCH)"
chmod +x kwokctl
sudo mv kwokctl /usr/local/bin/
```

## Usage

### Unified Command (Recommended)

Use the `kwok-cluster` command for all operations:

```bash
# Create clusters
./kwok-cluster create              # Create 10 clusters (default)
./kwok-cluster create 100         # Create 100 clusters
./kwok-cluster create 50 my-prefix # Create 50 with custom prefix

# Verify clusters
./kwok-cluster verify                    # Verify all clusters
./kwok-cluster verify kwok-cluster-0001  # Verify specific cluster

# List clusters
./kwok-cluster list

# Export contexts to default kubeconfig (makes them visible in terminal)
./kwok-cluster export-contexts              # Export all default clusters
./kwok-cluster export-contexts my-prefix    # Export with custom prefix

# Scale nodes in a cluster
./kwok-cluster scale kwok-cluster-0001 10

# Cleanup
./kwok-cluster cleanup              # Cleanup all default clusters
./kwok-cluster cleanup my-prefix    # Cleanup with custom prefix

# Help
./kwok-cluster help
```

### Verification Details

The `verify` command shows:
- API Server endpoint
- Health check status
- Ready check status
- Node count
- Overall cluster health
- Summary of all clusters

### Exporting Contexts

KWOK stores contexts in its own location. To export them to separate kubeconfig files (without modifying your default `~/.kube/config`), run:

```bash
# Export all KWOK contexts to ~/.kube/configs/
./kwok-cluster export-contexts

# This creates individual kubeconfig files:
# ~/.kube/configs/kwok-cluster-0001.yaml
# ~/.kube/configs/kwok-cluster-0002.yaml
# etc.
```

**To use an exported context:**

There are several ways to use the kubeconfig files:

**Method 1: Use KUBECONFIG environment variable (single file)**
```bash
# Use a specific cluster
export KUBECONFIG=~/.kube/configs/kwok-cluster-0001.yaml
kubectl get nodes
kubectl get contexts  # Will show the context from that file
```

**Method 2: Use --kubeconfig flag (single file)**
```bash
# Use a specific cluster without changing environment
kubectl --kubeconfig ~/.kube/configs/kwok-cluster-0001.yaml get nodes
```

**Method 3: Merge multiple kubeconfigs (all KWOK clusters at once)**
```bash
# Merge all KWOK configs with your default config
export KUBECONFIG=~/.kube/config:~/.kube/configs/kwok-cluster-0001.yaml:~/.kube/configs/kwok-cluster-0002.yaml

# Or merge all KWOK configs in the directory
export KUBECONFIG=~/.kube/config:$(ls -1 ~/.kube/configs/*.yaml | tr '\n' ':')

# Now all contexts are available
kubectl config get-contexts
kubectl --context kwok-kwok-cluster-0001 get nodes
```

**Method 4: Create a helper script to merge all**
```bash
# Add to your ~/.bashrc or ~/.zshrc
alias kwok-configs='export KUBECONFIG=~/.kube/config:$(ls -1 ~/.kube/configs/*.yaml 2>/dev/null | tr "\n" ":")'

# Then use:
kwok-configs
kubectl config get-contexts  # See all contexts including KWOK
```

**To delete all exported configs:**

```bash
rm -rf ~/.kube/configs/*.yaml
```

**Note**: This does NOT modify your default `~/.kube/config` file, keeping your main kubeconfig clean.

### Manual Commands

```bash
# List all clusters
kwokctl get clusters

# List available contexts (after export-contexts)
kubectl config get-contexts | grep kwok

# Check a specific cluster (clusters start empty - no nodes by default)
kubectl --context kwok-kwok-cluster-0001 get nodes
# Output: No resources found (this is expected - clusters start empty)
```

## Resources

- **Memory per cluster**: ~36KB/node
- **Best for**: Testing node scaling, scheduling
- **Documentation**: https://kwok.sigs.k8s.io/

