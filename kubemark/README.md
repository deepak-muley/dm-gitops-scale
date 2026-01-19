# Kubemark Scale Testing

Kubemark creates "hollow nodes" that register with the API server but don't run actual workloads. Best for API server load testing.

## Prerequisites

- Kubernetes cluster
- `kubectl` configured to access the cluster

## How It Works

Kubemark creates **"hollow nodes"** - lightweight node representations that register with the Kubernetes API server but don't run actual workloads. This is designed specifically for API server load testing.

### Hollow Node Architecture

A Kubemark hollow node is a pod that runs the `kubemark` binary with the `--morph=kubelet` flag. This binary:

1. **Registers as a Node**: Connects to the API server and registers itself as a Kubernetes node, appearing in `kubectl get nodes`.

2. **Simulates Kubelet Behavior**: Implements a subset of kubelet functionality:
   - Registers with the API server
   - Reports node status and conditions
   - Responds to API server health checks
   - Appears in node lists and scheduling decisions

3. **No Actual Workload Execution**: Unlike real kubelets, hollow nodes **don't run containers** or manage pod lifecycle. Pods can be scheduled to hollow nodes, but the containers never actually start.

### What Gets Created

When you create Kubemark hollow nodes:

```bash
./kubemark-cluster create 100
```

A Deployment is created with the specified number of replicas:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hollow-nodes
spec:
  replicas: 100
  template:
    spec:
      containers:
      - name: hollow-kubelet
        image: registry.k8s.io/kubemark:v1.29.0
        args:
        - --morph=kubelet
        - --name=$(NODE_NAME)
```

Each pod:
- Runs the Kubemark binary in kubelet mode
- Connects to the API server using credentials from a secret
- Registers itself as a node named after the pod (e.g., `hollow-node-xxx`)
- Consumes minimal resources (~50MB memory per node)

### How Node Registration Works

```
┌─────────────────────────────────────────┐
│  API Server                             │
│  ┌───────────────────────────────────┐  │
│  │  kubectl get nodes                │  │
│  │  → Shows 100 hollow nodes         │  │
│  └───────────────────────────────────┘  │
└────────────┬────────────────────────────┘
             │ Node registration & health checks
             ▼
┌─────────────────────────────────────────┐
│  Hollow Node Pods                       │
│  ┌──────────────────┐  ┌─────────────┐  │
│  │ hollow-node-xxx  │  │ hollow-...  │  │
│  │ (kubemark        │  │ ...         │  │
│  │  kubelet mode)   │  │ ...         │  │
│  └──────────────────┘  └─────────────┘  │
└─────────────────────────────────────────┘
```

Each hollow node pod:
- **Registers**: Creates a Node object in the API server
- **Heartbeats**: Sends periodic status updates to the API server
- **Responds**: Answers API server queries about node capacity, conditions, etc.

### What You Can Test

Kubemark is specifically designed for **API server load testing**:

1. **API Server Scaling**: Test how the API server handles thousands of nodes making API calls (heartbeats, status updates, etc.).

2. **Scheduler Performance**: Test the scheduler's behavior with many nodes without the overhead of actual node infrastructure.

3. **Controller Load**: Test how cluster controllers (node controller, replication controller, etc.) handle many nodes.

4. **etcd Performance**: Stress test etcd with high write/read loads from many nodes.

### Resource Usage

Each hollow node consumes:
- **~50MB memory** per node pod
- **Minimal CPU** (~20m request, ~100m limit)
- **No actual workload resources** (since no containers run)

This is more efficient than real nodes but heavier than KWOK's simulated nodes.

### Limitations

Hollow nodes have specific limitations:

1. **No Workload Execution**: Pods can be scheduled to hollow nodes, but containers never actually run.

2. **API Server Dependency**: Hollow nodes require the API server to be running and accessible.

3. **Testing-Focused**: Designed specifically for API server load testing, not for running applications.

4. **Setup Required**: Requires initial setup (namespace, secrets, permissions) before creating nodes.

### Differences from Other Methods

| Method | Node Type | Workload Execution | Best For |
|--------|-----------|-------------------|----------|
| **Kubemark** | Hollow (real API, no containers) | ❌ No | API server load testing |
| **KWOK** | Simulated (fake API) | ❌ No | Scheduling, API simulation |
| **vcluster** | Virtual cluster | ✅ Yes | Multi-tenancy, isolation |
| **Paused CAPI** | No nodes (API objects only) | ❌ No | GitOps, reconciliation |

## Usage

### Unified Command (Recommended)

Use the `kubemark-cluster` command for all operations:

```bash
# Setup (run once first)
./kubemark-cluster setup

# Create hollow nodes
./kubemark-cluster create              # Create 10 nodes (default)
./kubemark-cluster create 100         # Create 100 nodes
KUBEMARK_VERSION=v1.29.0 ./kubemark-cluster create 100

# Verify nodes
./kubemark-cluster verify

# Scale nodes
./kubemark-cluster scale 500

# List status
./kubemark-cluster list

# Cleanup
./kubemark-cluster cleanup

# Help
./kubemark-cluster help
```

### Manual Commands

```bash
# Check hollow node pods
kubectl get pods -n kubemark -l name=hollow-node

# Verify nodes appear in cluster
kubectl get nodes | grep hollow

# Check node count
kubectl get nodes --no-headers | wc -l

# To remove everything including namespace
kubectl delete namespace kubemark
```

## Resources

- **Memory per node**: ~50MB/node
- **Best for**: API server load testing
- **Note**: Hollow nodes register with the API server but don't run actual workloads

## Configuration

You can adjust the Kubemark version:

```bash
KUBEMARK_VERSION=v1.29.0 ./create-clusters.sh 100
```

## Troubleshooting

If nodes don't appear:

1. Check pod logs:
   ```bash
   kubectl logs -n kubemark -l name=hollow-node --tail=50
   ```

2. Verify kubeconfig secret:
   ```bash
   kubectl get secret kubeconfig -n kubemark -o yaml
   ```

3. Check API server connectivity from pods:
   ```bash
   kubectl exec -n kubemark <pod-name> -- curl -k https://kubernetes.default.svc/healthz
   ```

