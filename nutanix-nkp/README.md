# Nutanix NKP Scale Testing

Create NKP (Nutanix Kubernetes Platform) clusters for scale testing using the NKP CLI with `--dry-run -o yaml` to generate manifests, store them for GitOps, and optionally apply them to your NKP management cluster.

## Features

- **Named Parameters**: Full support for all NKP CLI options via command-line arguments
- **CSV Batch Creation**: Create multiple clusters from a CSV file
- **GitOps-Friendly**: Manifests stored in structured directory with Kustomize support
- **Dry-Run by Default**: Generate manifests without applying (review before deploy)
- **Config File Support**: Store common settings in `nkp.config`

## Prerequisites

### Required
- `kubectl` - Kubernetes command line tool
- `nkp` CLI - Nutanix Kubernetes Platform CLI from [Nutanix Portal](https://portal.nutanix.com/)
- Access to an NKP management cluster with valid kubeconfig

### NKP CLI Installation

Download from the Nutanix Portal or extract from an existing NKP cluster:

```bash
# Verify installation
nkp version
```

## Quick Start

### 1. Setup Configuration

```bash
# Copy and edit the config file
cp nkp.config.example nkp.config
vim nkp.config

# Or export environment variables
export MGMT_KUBECONFIG=/path/to/nkp-mgmt-kubeconfig
export NUTANIX_ENDPOINT=prism-central.example.com
export NUTANIX_PRISM_ELEMENT_CLUSTER=pe-cluster-1
# ... etc
```

### 2. Verify Setup

```bash
./nkp-cluster setup
```

### 3. Create Clusters

**From CSV (recommended for multiple clusters):**

```bash
# Generate CSV template
./nkp-cluster csv-template

# Edit with your cluster details
vim clusters.csv

# Generate manifests only (dry-run)
./nkp-cluster create --csv-file clusters.csv

# Generate and apply to management cluster
./nkp-cluster create --csv-file clusters.csv --apply
```

**Single cluster:**

```bash
./nkp-cluster create \
  --cluster-name my-cluster \
  --control-plane-endpoint-ip 10.0.1.100 \
  --service-lb-ip-range 10.1.1.100-10.1.1.110 \
  --apply
```

## CSV File Format

The CSV file defines cluster-specific parameters. Other settings come from `nkp.config` or environment variables.

```csv
cluster_name,namespace,control_plane_ip,service_lb_range,control_plane_replicas,worker_replicas
nkp-cluster-001,dm-dev-workspace,10.0.1.100,10.1.1.100-10.1.1.110,3,3
nkp-cluster-002,dm-dev-workspace,10.0.1.101,10.1.1.111-10.1.1.121,3,3
nkp-cluster-003,dm-staging,10.0.2.100,10.1.2.100-10.1.2.110,3,5
```

| Column | Description | Required |
|--------|-------------|----------|
| `cluster_name` | Unique cluster name | Yes |
| `namespace` | Target namespace | No (uses default) |
| `control_plane_ip` | Control plane VIP | Yes |
| `service_lb_range` | Service LoadBalancer IP range | Yes |
| `control_plane_replicas` | Number of control plane nodes | No (uses default) |
| `worker_replicas` | Number of worker nodes | No (uses default) |

## Output Structure

Manifests are stored in a GitOps-friendly directory structure:

```
clusters/
├── dm-dev-workspace/
│   ├── nkp-cluster-001/
│   │   ├── cluster.yaml        # Full NKP cluster manifest
│   │   └── kustomization.yaml  # Kustomize file
│   ├── nkp-cluster-002/
│   │   ├── cluster.yaml
│   │   └── kustomization.yaml
│   └── nkp-cluster-003/
│       ├── cluster.yaml
│       └── kustomization.yaml
├── dm-staging/
│   └── nkp-cluster-004/
│       ├── cluster.yaml
│       └── kustomization.yaml
└── dm-prod/
    └── nkp-cluster-005/
        ├── cluster.yaml
        └── kustomization.yaml
```

### Using with GitOps (Flux/ArgoCD)

The generated structure works directly with Flux or ArgoCD:

**Flux Kustomization:**

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: nkp-clusters
spec:
  path: ./clusters/dm-dev-workspace
  sourceRef:
    kind: GitRepository
    name: cluster-repo
```

**ArgoCD Application:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nkp-clusters
spec:
  source:
    path: clusters/dm-dev-workspace
    repoURL: https://github.com/your-org/cluster-repo
```

## Usage

### Commands

```bash
# Setup and verify configuration
./nkp-cluster setup

# Generate CSV template
./nkp-cluster csv-template

# Create clusters from CSV (manifests only)
./nkp-cluster create --csv-file clusters.csv

# Create clusters from CSV and apply
./nkp-cluster create --csv-file clusters.csv --apply

# Create single cluster
./nkp-cluster create \
  --cluster-name my-cluster \
  --namespace dm-dev-workspace \
  --control-plane-endpoint-ip 10.0.1.100 \
  --service-lb-ip-range 10.1.1.100-10.1.1.110 \
  --control-plane-replicas 3 \
  --worker-replicas 5 \
  --apply

# Verify clusters
./nkp-cluster verify --namespace dm-dev-workspace

# List clusters
./nkp-cluster list --namespace dm-dev-workspace

# Export single cluster manifest
./nkp-cluster export \
  --cluster-name my-cluster \
  --control-plane-endpoint-ip 10.0.1.100

# Cleanup specific cluster
./nkp-cluster cleanup --cluster-name my-cluster

# Cleanup all clusters in namespace
./nkp-cluster cleanup --namespace dm-dev-workspace

# Help
./nkp-cluster help
```

### Named Parameters

| Parameter | Short | Description | Default |
|-----------|-------|-------------|---------|
| `--cluster-name` | `-c` | Cluster name | (required) |
| `--namespace` | `-n` | Namespace | `dm-dev-workspace` |
| `--control-plane-endpoint-ip` | | Control plane VIP | (required) |
| `--service-lb-ip-range` | | Service LB IP range | |
| `--control-plane-replicas` | | Control plane nodes | 3 |
| `--worker-replicas` | | Worker nodes | 3 |
| `--endpoint` | | Nutanix endpoint | (from config) |
| `--port` | | Nutanix port | 9440 |
| `--prism-element-cluster` | | PE cluster name | (from config) |
| `--subnet` | | Network subnet | (from config) |
| `--storage-container` | | Storage container | (from config) |
| `--vm-image` | | VM image name | (from config) |
| `--ssh-public-key-file` | | SSH key file | (from config) |
| `--kubernetes-version` | | K8s version | v1.28.0 |
| `--worker-vcpus` | | Worker vCPUs | 4 |
| `--registry-url` | | Registry URL | |
| `--registry-username` | | Registry user | |
| `--registry-password` | | Registry pass | |
| `--kubeconfig` | | Mgmt kubeconfig | `$MGMT_KUBECONFIG` |
| `--config` | | Config file | `nkp.config` |
| `--csv-file` | | CSV input file | |
| `--dry-run` | | Generate only | (default) |
| `--apply` | | Apply to cluster | |

## Configuration

### Config File (`nkp.config`)

Store common settings in `nkp.config`:

```bash
# Copy the example
cp nkp.config.example nkp.config

# Edit with your values
vim nkp.config
```

Example `nkp.config`:

```bash
# Management Cluster
MGMT_KUBECONFIG="$HOME/.kube/nkp-mgmt-kubeconfig"

# Nutanix Infrastructure
NUTANIX_ENDPOINT="prism-central.example.com"
NUTANIX_PORT="9440"
NUTANIX_PRISM_ELEMENT_CLUSTER="pe-cluster-1"
NUTANIX_SUBNET="vm-network"
NUTANIX_STORAGE_CONTAINER="default-container"
NUTANIX_VM_IMAGE="nkp-ubuntu-22.04-1.28.0"
NUTANIX_SSH_KEY_FILE="$HOME/.ssh/id_rsa.pub"

# Kubernetes
KUBERNETES_VERSION="v1.28.0"
CONTROL_PLANE_REPLICAS="3"
WORKER_REPLICAS="3"
WORKER_VCPUS="4"

# Registry (optional, for air-gapped)
REGISTRY_URL=""
REGISTRY_USERNAME=""
REGISTRY_PASSWORD=""
```

### Environment Variables

All config file options can also be set via environment variables:

```bash
export MGMT_KUBECONFIG=/path/to/kubeconfig
export NUTANIX_ENDPOINT=prism.example.com
export NUTANIX_PRISM_ELEMENT_CLUSTER=pe-cluster-1
# ... etc

./nkp-cluster create --csv-file clusters.csv --apply
```

## Workflow Examples

### Example 1: Scale Testing with 100 Clusters

```bash
# 1. Setup config
cp nkp.config.example nkp.config
vim nkp.config

# 2. Generate CSV with your IP allocations
cat > clusters.csv << 'EOF'
cluster_name,namespace,control_plane_ip,service_lb_range,control_plane_replicas,worker_replicas
EOF

# Generate 100 clusters
for i in $(seq -w 1 100); do
  echo "nkp-scale-$i,scale-test,10.0.1.$i,10.1.$i.1-10.1.$i.20,1,2" >> clusters.csv
done

# 3. Generate manifests (review first)
./nkp-cluster create --csv-file clusters.csv

# 4. Review generated manifests
ls clusters/scale-test/
cat clusters/scale-test/nkp-scale-001/cluster.yaml

# 5. Apply all at once
./nkp-cluster create --csv-file clusters.csv --apply

# 6. Monitor
./nkp-cluster verify --namespace scale-test

# 7. Cleanup when done
./nkp-cluster cleanup --namespace scale-test
```

### Example 2: GitOps Workflow

```bash
# 1. Generate manifests
./nkp-cluster create --csv-file clusters.csv

# 2. Commit to git
cd clusters
git add .
git commit -m "Add NKP clusters for scale testing"
git push

# 3. Flux/ArgoCD will apply automatically
# Or apply manually:
kubectl --kubeconfig $MGMT_KUBECONFIG apply -k clusters/dm-dev-workspace/
```

### Example 3: Single Cluster Creation

```bash
# Quick single cluster
./nkp-cluster create \
  --cluster-name test-cluster \
  --control-plane-endpoint-ip 10.0.1.50 \
  --service-lb-ip-range 10.1.50.1-10.1.50.20 \
  --worker-replicas 5 \
  --apply

# Check status
./nkp-cluster verify --namespace dm-dev-workspace

# View manifest
cat clusters/dm-dev-workspace/test-cluster/cluster.yaml
```

## Differences from Other Methods

| Method | Manifest Generation | Kubeconfig | Best For |
|--------|---------------------|------------|----------|
| **Nutanix NKP** | NKP CLI `--dry-run` | Management cluster | Real NKP clusters |
| **KWOK** | Internal | Creates own | Scheduling simulation |
| **vcluster** | Internal | Host cluster | Multi-tenancy |
| **Paused CAPI** | Direct YAML | Any cluster | Generic GitOps |

## Troubleshooting

### NKP CLI Errors

```bash
# Verify NKP CLI is working
nkp version

# Test dry-run manually
nkp create cluster nutanix \
  -c test-cluster \
  --control-plane-endpoint-ip 10.0.0.1 \
  --dry-run -o yaml

# Check Prism connectivity
curl -k https://$NUTANIX_ENDPOINT:$NUTANIX_PORT/api/nutanix/v3/clusters/list
```

### Management Cluster Issues

```bash
# Verify kubeconfig
kubectl --kubeconfig $MGMT_KUBECONFIG cluster-info

# Check CAPI components
kubectl --kubeconfig $MGMT_KUBECONFIG get pods -n capi-system
kubectl --kubeconfig $MGMT_KUBECONFIG get pods -n capx-system
```

### CSV Parsing Issues

```bash
# Validate CSV format
head -5 clusters.csv

# Check for Windows line endings
file clusters.csv
# If needed, convert:
dos2unix clusters.csv
```

## Resources

- **NKP Documentation**: https://docs.nutanix.com/nkp/
- **NKP CLI Reference**: https://docs.nutanix.com/nkp/cli/
- **Cluster API**: https://cluster-api.sigs.k8s.io/
