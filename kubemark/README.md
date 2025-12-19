# Kubemark Scale Testing

Kubemark creates "hollow nodes" that register with the API server but don't run actual workloads. Best for API server load testing.

## Prerequisites

- Kubernetes cluster
- `kubectl` configured to access the cluster

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

