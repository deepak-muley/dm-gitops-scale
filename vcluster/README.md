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

## How It Works

vcluster creates **virtual Kubernetes clusters** that run inside a host Kubernetes cluster. Each vcluster provides a fully functional Kubernetes API and can run actual workloads, but shares the underlying infrastructure of the host cluster.

### Virtual Cluster Architecture

When you create a vcluster, it sets up:

1. **Virtual API Server**: A lightweight Kubernetes API server that runs as a pod in the host cluster. This API server is **real** - it's not simulated like KWOK.

2. **Syncer Component**: A syncer pod that translates between the virtual cluster's API and the host cluster's resources. When you create a Pod in the vcluster, the syncer creates a corresponding Pod in the host cluster (with namespace translation).

3. **Isolation**: Each vcluster runs in its own namespace in the host cluster, providing logical separation between virtual clusters.

### What Gets Created

When you create a vcluster:

```bash
vcluster create vc-0001 --namespace vcluster-0001
```

The following resources are created in the host cluster:

- **Namespace**: A dedicated namespace (e.g., `vcluster-0001`) for the vcluster
- **API Server Pod**: A pod running the vcluster's API server
- **Syncer Pod**: A pod that syncs resources between virtual and host clusters
- **Service**: A Kubernetes service exposing the API server
- **Secret**: A kubeconfig secret for connecting to the vcluster

### How Resource Sync Works

When you create a Pod in a vcluster:

```
┌─────────────────────────────────────────┐
│  Virtual Cluster (vc-0001)              │
│  ┌───────────────────────────────────┐  │
│  │  kubectl apply pod.yaml           │  │
│  │  → Creates Pod in vcluster API    │  │
│  └───────────────────────────────────┘  │
└────────────────┬────────────────────────┘
                 │ Syncer translates
                 ▼
┌─────────────────────────────────────────┐
│  Host Cluster (kind-vcluster-host)      │
│  ┌───────────────────────────────────┐  │
│  │  Pod created in vcluster-0001 ns  │  │
│  │  (with transformed metadata)      │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

The syncer:
- **Translates namespaces**: Resources in the vcluster's default namespace are created in the host cluster's vcluster namespace
- **Adds labels/annotations**: Adds metadata to identify resources belonging to the vcluster
- **Synchronizes status**: Updates resource status in the vcluster based on the host cluster's actual state

### What You Can Do

vclusters are **fully functional** Kubernetes clusters:

1. **Run Real Workloads**: Deploy actual applications, services, and containers that run in the host cluster.

2. **Complete API**: Full Kubernetes API support - create any Kubernetes resource (Deployments, Services, ConfigMaps, etc.).

3. **Multi-Tenancy**: Isolate teams or projects in separate vclusters while sharing the same host cluster infrastructure.

4. **Resource Sharing**: Multiple vclusters share the host cluster's nodes, storage, and networking, making efficient use of resources.

### Resource Usage

Each vcluster consumes:
- **~128MB memory** for API server and syncer pods
- **Host cluster resources** for any workloads you deploy
- **One namespace** in the host cluster

This is much lighter than real clusters but heavier than simulated approaches like KWOK or paused CAPI.

### Limitations

vclusters have some limitations:

1. **Host Cluster Dependency**: If the host cluster goes down, all vclusters are unavailable.

2. **Shared Infrastructure**: All vclusters share the same underlying nodes and storage.

3. **Network Isolation**: Network policies work within vclusters, but traffic flows through the host cluster's network.

4. **Privileged Operations**: Some privileged operations may not work due to the host cluster's security policies.

### Differences from Other Methods

| Method | Workload Execution | Resource Sharing | Use Case |
|--------|-------------------|------------------|----------|
| **vcluster** | ✅ Yes (runs in host) | Host cluster | Multi-tenancy, isolation |
| **KWOK** | ❌ No (simulated) | None | Scheduling, API testing |
| **Paused CAPI** | ❌ No (paused) | None | GitOps, reconciliation |
| **Kubemark** | ❌ No (hollow) | Host cluster | API server load testing |

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

