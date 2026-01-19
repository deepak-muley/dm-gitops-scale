# [TEMPLATE_NAME] Scale Testing

<!-- 
============================================================================
HOW TO ADAPT THIS README:
1. Replace all [PLACEHOLDER] values with your method's specifics
2. Update the "How It Works" section to explain your method
3. Add method-specific commands and configuration
4. Include relevant diagrams if helpful
============================================================================
-->

[TEMPLATE_NAME] is a method for creating Kubernetes clusters for scale testing.

## Prerequisites

Install `[TEMPLATE_TOOL]`:

```bash
# macOS
[INSTALL_COMMAND_MACOS]

# Linux
[INSTALL_COMMAND_LINUX]
```

You also need:
- `kubectl` - Kubernetes command line tool
- Access to a management cluster with valid kubeconfig

## How It Works

<!-- Explain how your method works -->

[TEMPLATE_NAME] creates clusters by using the CLI with `--dry-run` to generate manifests, then applying them to the management cluster.

### Workflow

```
┌─────────────────────────────────────────┐
│  [TEMPLATE_TOOL] CLI                    │
│  ┌───────────────────────────────────┐  │
│  │  create cluster --dry-run         │  │
│  │  → Generates YAML manifest        │  │
│  └───────────────────────────────────┘  │
└────────────┬────────────────────────────┘
             │ 
             ▼
┌─────────────────────────────────────────┐
│  kubectl apply -f manifest.yaml         │
│  → Applies to management cluster        │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│  Management Cluster                     │
│  ┌───────────────────────────────────┐  │
│  │  Cluster objects created          │  │
│  │  (paused or ready for provision)  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### What Gets Created

When you run:

```bash
./[template]-cluster create 100
```

The following resources are created:
- [List what gets created]
- [Be specific about resource types]

### Resource Usage

Each cluster consumes:
- **Memory**: ~[X]MB per cluster
- **CPU**: [describe CPU usage]
- **Storage**: [describe storage usage]

### What You Can Test

[TEMPLATE_NAME] is ideal for testing:

1. **[Use Case 1]**: [Description]
2. **[Use Case 2]**: [Description]
3. **[Use Case 3]**: [Description]

### Differences from Other Methods

| Method | What It Creates | Resource Usage | Best For |
|--------|----------------|----------------|----------|
| **[TEMPLATE_NAME]** | [description] | ~[X]MB/cluster | [use case] |
| **KWOK** | Simulated clusters + nodes | ~36KB/node | Scheduling, API simulation |
| **vcluster** | Virtual clusters | ~128MB/cluster | Multi-tenancy, isolation |
| **Paused CAPI** | API objects only | ~1KB/object | GitOps, reconciliation |

## Usage

### Unified Command (Recommended)

Use the `[template]-cluster` command for all operations:

```bash
# Setup - verify prerequisites
./[template]-cluster setup

# Create clusters
./[template]-cluster create              # Create 10 clusters (default)
./[template]-cluster create 100          # Create 100 clusters
./[template]-cluster create 50 my-ns     # Create 50 in custom namespace
./[template]-cluster create 50 my-ns /path/to/kubeconfig

# Verify clusters
./[template]-cluster verify
./[template]-cluster verify my-namespace /path/to/kubeconfig

# List clusters
./[template]-cluster list
./[template]-cluster list my-namespace /path/to/kubeconfig

# Export single cluster manifest
./[template]-cluster export my-cluster my-cluster.yaml

# Cleanup
./[template]-cluster cleanup
./[template]-cluster cleanup my-namespace /path/to/kubeconfig

# Help
./[template]-cluster help
```

### Environment Variables

```bash
# Set management cluster kubeconfig
export MGMT_KUBECONFIG=/path/to/management-cluster-kubeconfig

# Now commands use this kubeconfig automatically
./[template]-cluster create 100
```

| Variable | Description | Default |
|----------|-------------|---------|
| `MGMT_KUBECONFIG` | Path to management cluster kubeconfig | `$KUBECONFIG` or `~/.kube/config` |
| `[OTHER_VAR]` | [Description] | [default] |

### Manual Commands

```bash
# List all clusters
kubectl --kubeconfig $MGMT_KUBECONFIG get clusters -n dm-dev-workspace

# Check cluster status
kubectl --kubeconfig $MGMT_KUBECONFIG get clusters -n dm-dev-workspace -o wide

# Delete specific cluster
kubectl --kubeconfig $MGMT_KUBECONFIG delete cluster my-cluster -n dm-dev-workspace
```

## Resources

- **Memory per cluster**: ~[X]MB/cluster
- **Best for**: [primary use case]
- **Documentation**: [TOOL_DOCUMENTATION_URL]

## Troubleshooting

### Cannot Connect to Management Cluster

```bash
# Verify kubeconfig exists
ls -la $MGMT_KUBECONFIG

# Test connectivity
kubectl --kubeconfig $MGMT_KUBECONFIG cluster-info

# Check current context
kubectl --kubeconfig $MGMT_KUBECONFIG config current-context
```

### CLI Tool Not Found

```bash
# Verify installation
which [TEMPLATE_TOOL]

# Check version
[TEMPLATE_TOOL] version
```

### Permission Errors

Ensure you have appropriate RBAC permissions on the management cluster:
- Create/Delete Cluster resources
- Create/Delete namespaces (if needed)
