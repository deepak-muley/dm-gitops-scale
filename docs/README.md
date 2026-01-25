# Documentation Structure

This directory contains organized documentation for the dm-gitops-scale project.

## Directory Structure

```
docs/
├── bin-packing/          # Kubernetes resource bin packing guides
│   └── K8s-Resource-Bin-Packing-Guide.md
├── capi/                 # Cluster API (CAPI) related documentation
│   ├── CAPI-NUTANIX-OBJECT-MODEL.md
│   ├── CAPI-SCALING-SOLUTIONS-AND-FIXES.md
│   └── CLUSTER-API-SCALING-DEEP-DIVE.md
├── nkp/                  # Nutanix Kubernetes Platform (NKP) documentation
│   ├── NKP-CAPI-ADVANCED-SCALING-GUIDE.md
│   ├── NKP-Platform-Applications-Guide.md
│   └── NKP-Sizing-Scale-Guide.md
└── general/              # General guides and methods
    ├── ADDING-NEW-METHODS.md
    └── SCALE-TESTING.md
```

## Quick Links

### Bin Packing
- [Kubernetes Resource Bin Packing Guide](./bin-packing/K8s-Resource-Bin-Packing-Guide.md) - Complete guide on enabling and using resource bin packing

### Cluster API (CAPI)
- [CAPI Nutanix Object Model](./capi/CAPI-NUTANIX-OBJECT-MODEL.md) - CAPI object model for Nutanix
- [CAPI Scaling Solutions and Fixes](./capi/CAPI-SCALING-SOLUTIONS-AND-FIXES.md) - Solutions for CAPI scaling issues
- [Cluster API Scaling Deep Dive](./capi/CLUSTER-API-SCALING-DEEP-DIVE.md) - In-depth CAPI scaling guide

### Nutanix Kubernetes Platform (NKP)
- [NKP CAPI Advanced Scaling Guide](./nkp/NKP-CAPI-ADVANCED-SCALING-GUIDE.md) - Advanced NKP scaling with CAPI
- [NKP Platform Applications Guide](./nkp/NKP-Platform-Applications-Guide.md) - Platform applications overview
- [NKP Sizing & Scale Guide](./nkp/NKP-Sizing-Scale-Guide.md) - NKP sizing and scaling recommendations

### General
- [Adding New Methods](./general/ADDING-NEW-METHODS.md) - Guide for adding new scaling methods
- [Scale Testing](./general/SCALE-TESTING.md) - Scale testing methodologies and tools

## Running Bin Packing Examples

To run the bin packing demonstration scripts:

```bash
# Navigate to bin-packing directory
cd ../bin-packing

# Run kind cluster setup with MostAllocated strategy
./bin-packing-kind-setup.sh mostallocated

# Or use RequestedToCapacityRatio strategy
./bin-packing-kind-setup.sh requestedtocapacityratio
```

**Note:** The script requires:
- `kind` installed
- `kubectl` installed
- Docker running
- Proper permissions for kubeconfig file

If you encounter permission issues with kubeconfig:
```bash
# Fix kubeconfig permissions
chmod 600 ~/.kube/config
# Or remove lock file if stuck
rm -f ~/.kube/config.lock
```

## Documentation Updates

When adding new documentation:
1. Place it in the appropriate subdirectory based on topic
2. Update this README with a link
3. Update cross-references in related documents
