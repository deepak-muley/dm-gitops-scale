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

## How It Works

kube-burner is a **high-throughput object creation tool** designed for creating large numbers of Kubernetes objects quickly to test API server performance, controller behavior, and cluster scalability.

### Template-Based Creation

kube-burner uses **Go templates** to generate Kubernetes manifests, allowing you to create many similar objects with variations:

1. **Template Processing**: Reads YAML templates and processes them using Go template syntax (e.g., `{{.Iteration}}`, `{{.Namespace}}`).

2. **Batch Creation**: Creates objects in parallel batches with configurable QPS (queries per second) and burst limits to maximize throughput without overwhelming the API server.

3. **Iteration-Based**: Each iteration generates a unique object by replacing template variables, allowing creation of thousands of objects from a single template.

### What Gets Created

When you run kube-burner with a cluster template:

```bash
./kube-burner-cluster create 100
```

kube-burner processes the template (e.g., `templates/cluster.yaml`):

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: sim-cluster-{{.Iteration}}  # Template variable
  namespace: {{.Namespace}}
spec:
  paused: true
```

For each iteration (1 to 100), it:
- **Replaces variables**: `{{.Iteration}}` → `0001`, `0002`, etc.
- **Creates the object**: Sends the processed YAML to the API server
- **Tracks progress**: Monitors creation rate and errors

This results in 100 `Cluster` objects created rapidly.

### How High-Throughput Works

kube-burner optimizes for speed:

```
┌─────────────────────────────────────────┐
│  Template (templates/cluster.yaml)      │
│  ┌───────────────────────────────────┐  │
│  │  name: sim-cluster-{{.Iteration}} │  │
│  └───────────────────────────────────┘  │
└────────────┬────────────────────────────┘
             │ Parallel processing
             ▼
┌─────────────────────────────────────────┐
│  API Server                             │
│  ┌──────────────┐  ┌──────────────┐    │
│  │ Cluster 0001 │  │ Cluster 0002 │    │
│  └──────────────┘  └──────────────┘    │
│  ┌──────────────┐  ┌──────────────┐    │
│  │ Cluster 0003 │  │ Cluster 0004 │    │
│  └──────────────┘  └──────────────┘    │
│  ... (100+ objects created rapidly)    │
└─────────────────────────────────────────┘
```

Key features:
- **Parallel Creation**: Creates multiple objects simultaneously
- **QPS Control**: Configurable rate limiting (e.g., `QPS=100` for 100 requests/second)
- **Burst Control**: Handles burst traffic (e.g., `BURST=200` for 200 simultaneous requests)
- **Retry Logic**: Automatically retries failed requests

### What You Can Test

kube-burner is ideal for:

1. **API Server Performance**: Stress test the API server by creating thousands of objects rapidly.

2. **Controller Behavior**: Test how controllers (e.g., Cluster API controllers) handle large numbers of objects being created quickly.

3. **etcd Performance**: Measure etcd performance under high write loads.

4. **Cluster Scalability**: Test cluster limits by creating objects until you hit resource or API limits.

5. **Template Variations**: Easily test different object configurations by modifying templates.

### Template Customization

You can customize templates to create any Kubernetes object:

```yaml
# templates/cluster.yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: sim-cluster-{{.Iteration}}
  namespace: {{.Namespace}}
  labels:
    iteration: "{{.Iteration}}"
    batch: "scale-test"
spec:
  paused: true
  # ... cluster spec ...
```

Template variables available:
- `{{.Iteration}}`: Current iteration number (1, 2, 3, ...)
- `{{.Namespace}}`: Target namespace
- `{{.Index}}`: Zero-based index (0, 1, 2, ...)
- Custom variables via `--template-vars`

### Resource Usage

kube-burner itself is lightweight:
- **Minimal memory** - just processes templates and makes API calls
- **No cluster resources** - doesn't create pods or consume cluster CPU/memory
- **Depends on created objects** - resource usage depends on what objects you create (e.g., paused CAPI clusters use ~1KB each)

### Configuration Options

Control creation rate:

```bash
# Lower QPS for slower API servers
QPS=20 BURST=40 ./kube-burner-cluster create 1000

# Higher QPS for faster API servers
QPS=100 BURST=200 ./kube-burner-cluster create 1000
```

- **QPS**: Queries per second (sustained rate)
- **BURST**: Maximum simultaneous requests (peak rate)

### Differences from Other Methods

| Method | What It Does | Speed | Best For |
|--------|-------------|-------|----------|
| **kube-burner** | Creates many objects rapidly | ⚡ Very Fast | API load testing, bulk creation |
| **KWOK** | Simulates clusters/nodes | ⚠️ Moderate | Scheduling, node simulation |
| **vcluster** | Creates virtual clusters | ⚠️ Moderate | Multi-tenancy, isolation |
| **Paused CAPI** | Creates paused CAPI objects | ⚠️ Moderate | GitOps, reconciliation |

**Note**: kube-burner is not a cluster simulation tool - it's an **object creation tool**. It's often used to create paused CAPI objects (as in this repository), but it can create any Kubernetes objects from templates.

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

