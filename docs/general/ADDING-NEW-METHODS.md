# Adding New Cluster Creation Methods

This guide explains how to add a new cluster creation method to this repository using the provided template.

## Quick Start

```bash
# 1. Copy the template folder
cp -r cluster-create-template your-method-name

# 2. Rename the main script
mv your-method-name/template-cluster your-method-name/your-method-name-cluster

# 3. Make it executable
chmod +x your-method-name/your-method-name-cluster

# 4. Edit the script and README (see detailed instructions below)
```

## Template Structure

The `cluster-create-template/` folder contains:

```
cluster-create-template/
├── template-cluster           # Main executable script (copy & rename)
├── README.md                  # Documentation template
└── templates/
    └── cluster.yaml.template  # Optional: manifest templates
```

## Step-by-Step Guide

### Step 1: Copy the Template

```bash
# Example: Creating a method for Rancher
cp -r cluster-create-template rancher

# Example: Creating a method for OpenShift
cp -r cluster-create-template openshift
```

### Step 2: Rename the Main Script

The script name should follow the pattern `<method-name>-cluster`:

```bash
# For Rancher
mv rancher/template-cluster rancher/rancher-cluster

# For OpenShift
mv openshift/template-cluster openshift/openshift-cluster
```

### Step 3: Make the Script Executable

```bash
chmod +x rancher/rancher-cluster
```

### Step 4: Update the Script

Open the script and update the following sections:

#### 4.1 Header and Description

```bash
# Before:
# [TEMPLATE_NAME] Cluster Management Script
# Usage: ./template-cluster <command> [options]

# After (example for Rancher):
# Rancher Cluster Management Script
# Usage: ./rancher-cluster <command> [options]
```

#### 4.2 Configuration Variables

```bash
# Before:
DEFAULT_NAMESPACE="dm-dev-workspace"
DEFAULT_PREFIX="[template]-cluster"

# After (example for Rancher):
DEFAULT_NAMESPACE="dm-dev-workspace"
DEFAULT_PREFIX="rancher-cluster"
```

#### 4.3 Tool Check Function

Create a function to check if your method's CLI tool is installed:

```bash
# Before:
check_[template]_tool() {
    if ! command -v [TEMPLATE_TOOL] &> /dev/null; then
        ...
    fi
}

# After (example for Rancher):
check_rancher() {
    if ! command -v rancher &> /dev/null; then
        echo "ERROR: rancher CLI is not installed"
        echo ""
        echo "Install from: https://ranchermanager.docs.rancher.com/reference-guides/cli-with-rancher/rancher-cli"
        exit 1
    fi
}
```

#### 4.4 Implement Core Commands

The template assumes you'll use a CLI tool with `--dry-run` to generate manifests:

**cmd_create()** - Most important function:

```bash
cmd_create() {
    local COUNT="${1:-$DEFAULT_COUNT}"
    local NAMESPACE="${2:-$DEFAULT_NAMESPACE}"
    local KUBECONFIG_ARG="${3:-$MGMT_KUBECONFIG}"
    
    check_kubectl
    check_rancher  # Your tool check
    check_mgmt_cluster "$KUBECONFIG_ARG"
    
    echo "Creating $COUNT Rancher clusters..."
    
    for i in $(seq 1 $COUNT); do
        cluster_name="rancher-cluster-$(printf "%04d" $i)"
        
        # Generate manifest using CLI --dry-run
        MANIFEST_FILE=$(mktemp)
        
        if rancher cluster create "$cluster_name" --dry-run -o yaml > "$MANIFEST_FILE"; then
            # Apply to management cluster
            if kubectl --kubeconfig "$KUBECONFIG_ARG" apply -f "$MANIFEST_FILE" -n "$NAMESPACE"; then
                echo "  ✓ Created $cluster_name"
            fi
        fi
        
        rm -f "$MANIFEST_FILE"
    done
}
```

**cmd_verify()** - Check cluster status:

```bash
cmd_verify() {
    local NAMESPACE="${1:-$DEFAULT_NAMESPACE}"
    local KUBECONFIG_ARG="${2:-$MGMT_KUBECONFIG}"
    
    echo "Verifying Rancher clusters..."
    
    kubectl --kubeconfig "$KUBECONFIG_ARG" get clusters -n "$NAMESPACE" -l provider=rancher
}
```

**cmd_cleanup()** - Delete clusters:

```bash
cmd_cleanup() {
    local NAMESPACE="${1:-$DEFAULT_NAMESPACE}"
    local KUBECONFIG_ARG="${2:-$MGMT_KUBECONFIG}"
    
    echo "Cleaning up Rancher clusters..."
    
    kubectl --kubeconfig "$KUBECONFIG_ARG" delete clusters -n "$NAMESPACE" -l provider=rancher --wait=false
}
```

**cmd_export()** - Export single cluster manifest:

```bash
cmd_export() {
    local CLUSTER_NAME="${1:-}"
    local OUTPUT_FILE="${2:-${CLUSTER_NAME}.yaml}"
    
    echo "Exporting cluster manifest..."
    
    rancher cluster create "$CLUSTER_NAME" --dry-run -o yaml > "$OUTPUT_FILE"
    echo "✓ Exported to: $OUTPUT_FILE"
}
```

### Step 5: Update the README

Update `your-method-name/README.md` with:

1. **Title and description** of your method
2. **Prerequisites** - CLI tool installation
3. **How It Works** - explain the --dry-run workflow
4. **Resource Usage** - memory/CPU per cluster
5. **Usage examples** - show actual commands with kubeconfig
6. **Environment Variables** - especially `MGMT_KUBECONFIG`
7. **Troubleshooting** - common issues

### Step 6: Add Templates (Optional)

If your method uses manifest templates instead of CLI --dry-run:

1. Keep the `templates/` folder
2. Create your template files
3. Update the script to use them

If using CLI --dry-run exclusively, you can delete the `templates/` folder.

### Step 7: Update Main README

Add your method to the main `README.md` table:

```markdown
| Method | Resources per "Cluster" | Best For | Folder |
|--------|------------------------|----------|--------|
| **Your Method** | ~XMB/cluster | Your use case | [`your-method/`](./your-method/) |
```

### Step 8: Test Your Implementation

```bash
cd your-method-name

# Set management cluster kubeconfig
export MGMT_KUBECONFIG=/path/to/mgmt-kubeconfig

# Test help
./your-method-cluster help

# Test setup
./your-method-cluster setup

# Test create (start small)
./your-method-cluster create 2

# Test verify
./your-method-cluster verify

# Test list
./your-method-cluster list

# Test export
./your-method-cluster export test-cluster test.yaml

# Test cleanup
./your-method-cluster cleanup
```

## Checklist for New Methods

- [ ] Copied `cluster-create-template/` to new folder
- [ ] Renamed script to `<method>-cluster`
- [ ] Made script executable (`chmod +x`)
- [ ] Updated script header/description
- [ ] Updated configuration variables
- [ ] Implemented `check_<tool>()` function
- [ ] Implemented `cmd_setup()`
- [ ] Implemented `cmd_create()` with CLI --dry-run
- [ ] Implemented `cmd_verify()`
- [ ] Implemented `cmd_cleanup()`
- [ ] Implemented `cmd_list()`
- [ ] Implemented `cmd_export()`
- [ ] Updated `cmd_help()` with method-specific info
- [ ] Updated README.md with documentation
- [ ] Tested all commands with real kubeconfig
- [ ] Updated main README.md

## Common Patterns

### Pattern 1: CLI with --dry-run (Recommended)

Most modern CLIs support `--dry-run` to generate manifests:

```bash
# NKP
nkp create cluster nutanix --cluster-name my-cluster --dry-run -o yaml

# Rancher
rancher cluster create my-cluster --dry-run -o yaml

# Tanzu
tanzu cluster create my-cluster --dry-run > manifest.yaml
```

This approach:
- Uses the official CLI to generate correct manifests
- Supports all CLI options and validations
- Works with any management cluster

### Pattern 2: Management Cluster Kubeconfig

All commands should accept kubeconfig as argument or environment variable:

```bash
# Via environment variable
export MGMT_KUBECONFIG=/path/to/kubeconfig
./your-method-cluster create 100

# Via argument
./your-method-cluster create 100 my-namespace /path/to/kubeconfig
```

### Pattern 3: Labels for Identification

Always add labels to identify your clusters:

```yaml
metadata:
  labels:
    provider: "your-method"
    simulation: "true"
    batch: "scale-test"
```

This allows easy filtering:

```bash
kubectl get clusters -l provider=your-method
kubectl delete clusters -l provider=your-method
```

### Pattern 4: Manifest Export Command

Include an `export` command to generate a single cluster manifest:

```bash
# Export for review
./your-method-cluster export my-cluster my-cluster.yaml

# Review the manifest
cat my-cluster.yaml

# Apply manually if needed
kubectl apply -f my-cluster.yaml
```

## Example: Complete Implementation

See [`nutanix-nkp/`](../nutanix-nkp/) for a complete example showing:

- NKP CLI integration with `--dry-run`
- Management cluster kubeconfig handling
- Multiple provider support (nutanix, aws, azure, vsphere)
- Simulation mode for testing without actual CLI
- Export command for single manifests

## Key Placeholders to Replace

| Placeholder | Replace With | Example |
|-------------|--------------|---------|
| `[TEMPLATE_NAME]` | Full method name | `Rancher` |
| `[template]` | Lowercase short name | `rancher` |
| `[TEMPLATE_TOOL]` | CLI tool name | `rancher` |
| `[INSTALL_COMMAND_*]` | Installation commands | `brew install rancher-cli` |
| `[TOOL_DOCUMENTATION_URL]` | Docs link | `https://rancher.com/docs` |

## Troubleshooting

### Script Not Executable

```bash
chmod +x your-method-name/your-method-cluster
```

### Cannot Connect to Management Cluster

```bash
# Verify kubeconfig
cat $MGMT_KUBECONFIG

# Test connection
kubectl --kubeconfig $MGMT_KUBECONFIG cluster-info
```

### CLI --dry-run Not Working

Some CLIs require additional setup before --dry-run works:

```bash
# Login/authenticate first
your-tool login

# Then dry-run should work
your-tool create cluster --dry-run -o yaml
```

## Contributing

When adding a new method:

1. Follow the existing folder structure
2. Use consistent naming conventions
3. Include comprehensive documentation
4. Test all commands before submitting
5. Add your method to the main README
