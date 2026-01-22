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

### Understanding Syncer Replicas

The **syncer** is a critical component that bridges the virtual cluster API and the host cluster. It's responsible for:

1. **Watching** the virtual cluster API for resource changes
2. **Translating** virtual cluster resources to host cluster resources
3. **Syncing** resource status back from host to virtual cluster
4. **Managing** resource lifecycle (create, update, delete)

#### What Are Syncer Replicas?

Syncer replicas are multiple instances of the syncer component running in parallel. By default, vcluster runs **1 syncer pod**, but you can configure multiple replicas for:

- **High Availability**: If one syncer pod fails, others continue working
- **Performance**: Multiple syncers can handle more concurrent resource operations
- **Load Distribution**: Workload is distributed across multiple syncer pods

#### How Syncer Replicas Work

**Example 1: Single Syncer (Default)**

```
Virtual Cluster API
       │
       │ All operations go through
       ▼
┌──────────────────────┐
│  Syncer Pod (1)      │  ← Single point of sync
│  - Watches API       │
│  - Translates        │
│  - Syncs status      │
└──────────┬───────────┘
           │
           ▼
    Host Cluster
```

**Example 2: Multiple Syncer Replicas (3 replicas)**

```
Virtual Cluster API
       │
       │ Operations distributed across syncers
       ├──────────────┬──────────────┐
       ▼              ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│ Syncer 1 │  │ Syncer 2 │  │ Syncer 3 │  ← Multiple syncers
│ Pod      │  │ Pod      │  │ Pod      │     share the workload
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │
     └─────────────┴─────────────┘
                    │
                    ▼
             Host Cluster
```

#### Practical Example: Creating Resources with Multiple Syncers

**Scenario**: You create 100 pods in your vcluster simultaneously.

**With 1 Syncer Replica:**
```bash
# All 100 pod creations processed sequentially by 1 syncer
kubectl apply -f 100-pods.yaml  # Takes ~30 seconds
```

**With 3 Syncer Replicas:**
```bash
# Workload distributed across 3 syncers
kubectl apply -f 100-pods.yaml  # Takes ~10 seconds (3x faster)
```

The syncers coordinate using leader election - they share the workload but don't duplicate work.

#### Example: Creating vcluster with Syncer Replicas

```bash
# Create vcluster with 1 control plane and 3 syncer replicas
./vcluster-cluster create 10 vcluster 1 3

# Or using named parameters
./vcluster-cluster create \
  --count 10 \
  --control-plane-replicas 1 \
  --syncer-replicas 3
```

**What happens:**
1. Creates 10 vclusters
2. Each vcluster has 1 API server replica (for HA)
3. Each vcluster has 3 syncer pods (for performance/HA)

**Check the syncers:**
```bash
# List syncer pods for a vcluster
kubectl get pods -n vcluster-0001 | grep syncer

# Output:
# vc-0001-0-syncer-7d8f9c4b5-abc12   1/1   Running   0   2m
# vc-0001-0-syncer-7d8f9c4b5-def34   1/1   Running   0   2m
# vc-0001-0-syncer-7d8f9c4b5-ghi56   1/1   Running   0   2m
```

#### When to Use Multiple Syncer Replicas

**Use 1 syncer replica (default) when:**
- Low to moderate resource creation rate
- Small number of resources
- Cost/resource optimization is priority

**Use 3+ syncer replicas when:**
- High resource creation rate (many deployments/pods)
- Need high availability (can't afford syncer downtime)
- Large-scale operations (100+ resources at once)
- Performance is critical

#### Real-World Example: Batch Deployment

```bash
# Scenario: Deploy 50 microservices to vcluster

# With 1 syncer (default)
time kubectl apply -f microservices/  # Takes 2 minutes

# With 3 syncers
./vcluster-cluster create vc-prod --syncer-replicas 3
time kubectl apply -f microservices/  # Takes 45 seconds
```

#### Syncer Replica Coordination

Multiple syncer replicas use **leader election** to coordinate:

1. **Leader**: Handles resource creation/updates
2. **Followers**: Standby, ready to take over if leader fails
3. **Load Distribution**: Work is distributed across all active syncers

This ensures:
- No duplicate operations
- Automatic failover
- Better performance under load

#### Monitoring Syncer Performance

```bash
# Check syncer pod status
kubectl get pods -n vcluster-0001 -l app=syncer

# Check syncer logs
kubectl logs -n vcluster-0001 -l app=syncer --tail=100

# Monitor syncer resource usage
kubectl top pods -n vcluster-0001 | grep syncer
```

#### Summary: Syncer Replicas

| Aspect | 1 Replica (Default) | 3+ Replicas |
|--------|---------------------|-------------|
| **Availability** | Single point of failure | High availability |
| **Performance** | Sequential processing | Parallel processing |
| **Resource Usage** | Lower (~50MB) | Higher (~150MB for 3) |
| **Use Case** | Small workloads | Large/high-availability workloads |
| **Failover** | Manual restart needed | Automatic |

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

## Kubernetes Version Configuration

### Specifying Kubernetes Version

vcluster allows you to specify which Kubernetes version the virtual cluster's API server should use. This is controlled via the API server image tag in the Helm chart.

**Usage:**

```bash
# Using named parameter
./vcluster-cluster create --count 10 --kubernetes-version v1.28.0

# Using short alias
./vcluster-cluster create --count 10 -k v1.28.0

# Using positional arguments
./vcluster-cluster create 10 vcluster 1 3 v1.28.0
# Format: COUNT PREFIX CONTROL_PLANE_REPLICAS SYNCER_REPLICAS KUBERNETES_VERSION

# Version format (with or without 'v' prefix)
./vcluster-cluster create 10 -k 1.28.0    # Works
./vcluster-cluster create 10 -k v1.28.0    # Also works
```

### Supported Kubernetes Versions

vcluster supports a wide range of Kubernetes versions. The exact versions available depend on:

1. **vcluster chart version**: Newer chart versions support newer Kubernetes versions
2. **API server image availability**: The Kubernetes API server images must be available in the container registry

**Commonly supported versions:**
- Kubernetes 1.24.x through 1.30.x (and newer as they're released)
- The exact range depends on your vcluster chart version

**To check available versions:**

1. Check the vcluster Helm chart values:
   ```bash
   helm show values loft-sh/vcluster
   ```

2. Check available Kubernetes API server images:
   ```bash
   # The API server image is typically: registry.k8s.io/kube-apiserver:<version>
   # Or check vcluster's default values
   ```

3. Check vcluster documentation:
   - Visit: https://www.vcluster.com/docs
   - Check release notes for version compatibility

**How it works:**

When you specify `--kubernetes-version v1.28.0`, the script sets the Helm value:
```yaml
api.image.tag: v1.28.0
```

This tells vcluster to use the Kubernetes API server image tagged with that version. The vcluster API server pod will run that specific Kubernetes version, making the virtual cluster appear as that Kubernetes version to clients.

**Note:** The Helm value path (`api.image.tag`) may vary slightly between vcluster chart versions. If you encounter issues, check your specific chart version's values:
```bash
helm show values loft-sh/vcluster --version <your-chart-version>
```

**Troubleshooting:**

If version specification fails:
1. Verify the version format (e.g., `v1.28.0` or `1.28.0`)
2. Check if the image tag exists in the registry
3. Verify the Helm value path for your vcluster chart version
4. Use `--set` with the correct path if needed:
   ```bash
   ./vcluster-cluster create 10 --set "api.image.tag=v1.28.0"
   ```

## Quick Reference: Syncer Replicas

### Command Examples

```bash
# Default: 1 syncer replica
./vcluster-cluster create 10

# 3 syncer replicas for better performance
./vcluster-cluster create 10 vcluster 1 3

# Using named parameters
./vcluster-cluster create \
  --count 10 \
  --control-plane-replicas 1 \
  --syncer-replicas 3

# Verify syncer replicas are running
kubectl get deployment -n vcluster-0001 | grep syncer
kubectl get pods -n vcluster-0001 | grep syncer
```

### When to Use Multiple Syncers

- ✅ **Use 3+ replicas**: High-traffic workloads, batch operations, HA requirements
- ✅ **Use 1 replica**: Small workloads, cost optimization, simple deployments

### Key Points

- **Syncer replicas ≠ Worker nodes**: Syncers are control plane components, not compute nodes
- **Workloads run in host cluster**: Your pods/deployments use the host cluster's nodes
- **Leader election**: Multiple syncers coordinate automatically
- **Performance**: More syncers = faster resource synchronization

## Notes

- Each vcluster runs in its own namespace
- vclusters are functional Kubernetes clusters that can run workloads
- Much lighter than real clusters but heavier than KWOK or paused CAPI objects
- Syncer replicas improve performance and availability, not compute capacity

