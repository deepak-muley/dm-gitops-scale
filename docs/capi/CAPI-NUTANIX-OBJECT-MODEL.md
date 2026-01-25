# Cluster API + Nutanix Provider Object Model & Architecture

This document provides a comprehensive object model, block diagrams, and detailed explanations of how Cluster API (CAPI) resources relate to Nutanix-specific infrastructure provider objects (CAPX - Cluster API Provider for Nutanix), including controller interfaces, callbacks, and Cloud Controller Manager integration.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Cluster API Objects](#core-cluster-api-objects)
3. [Nutanix Infrastructure Provider Objects (CAPX)](#nutanix-infrastructure-provider-objects-capx)
4. [Object Relationships & References](#object-relationships--references)
5. [Block Diagrams](#block-diagrams)
6. [Controller Interfaces & Contracts](#controller-interfaces--contracts)
7. [Reconciliation Flow](#reconciliation-flow)
8. [Cloud Controller Manager Integration](#cloud-controller-manager-integration)
9. [Example YAML Manifests](#example-yaml-manifests)
10. [References](#references)

---

## Architecture Overview

### High-Level Component View

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              MANAGEMENT CLUSTER                                       │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                       │
│  ┌───────────────────────────────────────────────────────────────────────────────┐   │
│  │                        Kubernetes API Server                                   │   │
│  │   Serves CRDs: Cluster, Machine, MachineDeployment, NutanixCluster, etc.      │   │
│  └───────────────────────────────────────────────────────────────────────────────┘   │
│                                           │                                           │
│           ┌───────────────────────────────┼───────────────────────────────┐          │
│           │                               │                               │          │
│           ▼                               ▼                               ▼          │
│  ┌─────────────────┐            ┌─────────────────┐            ┌─────────────────┐  │
│  │   CAPI Core     │            │   Bootstrap     │            │  Control Plane  │  │
│  │  Controllers    │            │   Provider      │            │    Provider     │  │
│  │ ─────────────── │            │ (Kubeadm)       │            │   (Kubeadm)     │  │
│  │ • Cluster       │            │ ─────────────── │            │ ─────────────── │  │
│  │ • Machine       │            │ • KubeadmConfig │            │ • KubeadmCP     │  │
│  │ • MachineSet    │            │ • Bootstrap     │            │                 │  │
│  │ • MachineDepl.  │            │   secrets       │            │                 │  │
│  └─────────────────┘            └─────────────────┘            └─────────────────┘  │
│           │                               │                               │          │
│           └───────────────────────────────┼───────────────────────────────┘          │
│                                           │                                           │
│                                           ▼                                           │
│  ┌───────────────────────────────────────────────────────────────────────────────┐   │
│  │              CAPX - Cluster API Provider for Nutanix                          │   │
│  │   ─────────────────────────────────────────────────────────────────────────   │   │
│  │   Controllers:                                                                 │   │
│  │   • NutanixCluster Controller                                                 │   │
│  │   • NutanixMachine Controller                                                 │   │
│  │   • NutanixMachineTemplate Controller                                         │   │
│  │                                                                                │   │
│  │   CRDs Managed:                                                               │   │
│  │   • NutanixCluster (infrastructure.cluster.x-k8s.io/v1beta1)                 │   │
│  │   • NutanixMachine (infrastructure.cluster.x-k8s.io/v1beta1)                 │   │
│  │   • NutanixMachineTemplate (infrastructure.cluster.x-k8s.io/v1beta1)         │   │
│  └───────────────────────────────────────────────────────────────────────────────┘   │
│                                           │                                           │
│                                           │ API Calls                                 │
│                                           ▼                                           │
│  ┌───────────────────────────────────────────────────────────────────────────────┐   │
│  │                        Nutanix Prism Central API                               │   │
│  │   • VM Creation/Deletion                                                       │   │
│  │   • Network Configuration                                                      │   │
│  │   • Storage Provisioning                                                       │   │
│  │   • Image Management                                                           │   │
│  └───────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                           │
                                           │ Creates & Manages
                                           ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              WORKLOAD CLUSTER(s)                                     │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────────────────────────┐   │
│  │   Control Plane Nodes (VMs on Nutanix AHV)                                    │   │
│  │   • kube-apiserver, etcd, scheduler, controller-manager                       │   │
│  │   • cloud-controller-manager (Nutanix)                                        │   │
│  └───────────────────────────────────────────────────────────────────────────────┘   │
│  ┌───────────────────────────────────────────────────────────────────────────────┐   │
│  │   Worker Nodes (VMs on Nutanix AHV)                                           │   │
│  │   • kubelet, kube-proxy, container runtime                                    │   │
│  │   • Nutanix CSI Driver                                                        │   │
│  └───────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Core Cluster API Objects

### API Groups

| API Group | Description |
|-----------|-------------|
| `cluster.x-k8s.io/v1beta1` | Core CAPI resources |
| `bootstrap.cluster.x-k8s.io/v1beta1` | Bootstrap provider resources |
| `controlplane.cluster.x-k8s.io/v1beta1` | Control plane provider resources |
| `infrastructure.cluster.x-k8s.io/v1beta1` | Infrastructure provider resources (Nutanix) |

### Core Resources Table

| Resource | Kind | Purpose | Key Spec Fields |
|----------|------|---------|-----------------|
| **Cluster** | `cluster.x-k8s.io/v1beta1` | Top-level cluster definition; references infrastructure and control plane | `spec.infrastructureRef`, `spec.controlPlaneRef`, `spec.clusterNetwork`, `spec.topology` |
| **Machine** | `cluster.x-k8s.io/v1beta1` | Represents a single node (control plane or worker) | `spec.clusterName`, `spec.infrastructureRef`, `spec.bootstrap`, `spec.version`, `spec.failureDomain` |
| **MachineSet** | `cluster.x-k8s.io/v1beta1` | Manages a set of Machines (like ReplicaSet for Pods) | `spec.replicas`, `spec.selector`, `spec.template` |
| **MachineDeployment** | `cluster.x-k8s.io/v1beta1` | Declarative worker pool management with rollout strategy | `spec.replicas`, `spec.strategy`, `spec.template`, `spec.minReadySeconds` |
| **MachinePool** | `cluster.x-k8s.io/v1beta1` (experimental) | Group-level machine abstraction | `spec.replicas`, `spec.template`, `spec.failureDomains` |
| **ClusterClass** | `cluster.x-k8s.io/v1beta1` | Reusable cluster template with variables and patches | `spec.infrastructure`, `spec.controlPlane`, `spec.workers`, `spec.variables` |
| **KubeadmControlPlane** | `controlplane.cluster.x-k8s.io/v1beta1` | Control plane management using kubeadm | `spec.replicas`, `spec.version`, `spec.kubeadmConfigSpec`, `spec.machineTemplate` |
| **KubeadmConfig** | `bootstrap.cluster.x-k8s.io/v1beta1` | Bootstrap configuration for kubeadm | `spec.initConfiguration`, `spec.joinConfiguration`, `spec.files`, `spec.users` |
| **KubeadmConfigTemplate** | `bootstrap.cluster.x-k8s.io/v1beta1` | Template for KubeadmConfig | `spec.template` |

### Cluster Resource Detail

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-cluster
  namespace: default
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["192.168.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
    serviceDomain: "cluster.local"
  
  # Reference to Infrastructure Provider (NutanixCluster)
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: NutanixCluster
    name: my-cluster
    namespace: default
  
  # Reference to Control Plane Provider
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: my-cluster-control-plane
    namespace: default
  
  # Optional: Topology for ClusterClass-based clusters
  topology:
    class: my-cluster-class
    version: v1.28.0
    controlPlane:
      replicas: 3
    workers:
      machineDeployments:
        - class: default-worker
          name: md-0
          replicas: 3

status:
  phase: Provisioned
  infrastructureReady: true
  controlPlaneReady: true
  conditions:
    - type: Ready
      status: "True"
```

### Machine Resource Detail

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Machine
metadata:
  name: my-cluster-worker-0
  namespace: default
  labels:
    cluster.x-k8s.io/cluster-name: my-cluster
  ownerReferences:
    - apiVersion: cluster.x-k8s.io/v1beta1
      kind: MachineSet
      name: my-cluster-md-0-abc123
spec:
  clusterName: my-cluster
  version: "v1.28.0"
  
  # Reference to Infrastructure Machine (NutanixMachine)
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: NutanixMachine
    name: my-cluster-worker-0
    namespace: default
  
  # Bootstrap configuration reference
  bootstrap:
    configRef:
      apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
      kind: KubeadmConfig
      name: my-cluster-worker-0
    dataSecretName: my-cluster-worker-0-bootstrap

status:
  phase: Running
  bootstrapReady: true
  infrastructureReady: true
  nodeRef:
    apiVersion: v1
    kind: Node
    name: my-cluster-worker-0
  addresses:
    - type: InternalIP
      address: 10.0.0.15
```

---

## Nutanix Infrastructure Provider Objects (CAPX)

### NutanixCluster

The `NutanixCluster` resource defines the infrastructure-level configuration for a cluster on Nutanix, including Prism Central connection details and control plane endpoint.

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: NutanixCluster
metadata:
  name: my-cluster
  namespace: default
  ownerReferences:
    - apiVersion: cluster.x-k8s.io/v1beta1
      kind: Cluster
      name: my-cluster
spec:
  # Control Plane endpoint (VIP or load balancer)
  controlPlaneEndpoint:
    host: "10.0.0.100"
    port: 6443
  
  # Prism Central connection configuration
  prismCentral:
    address: "prism-central.example.com"
    port: 9440
    insecure: false
    credentialRef:
      kind: Secret
      name: nutanix-credentials
      namespace: default
    additionalTrustBundle:
      kind: ConfigMap
      name: nutanix-trust-bundle
      namespace: default
  
  # Optional: Failure domains for HA
  failureDomains:
    - name: fd-1
      cluster:
        type: name
        name: "nutanix-cluster-1"
      subnets:
        - type: name
          name: "vm-network-1"

status:
  ready: true
  failureDomains:
    fd-1:
      controlPlane: true
      attributes:
        cluster: "nutanix-cluster-1"
  conditions:
    - type: Ready
      status: "True"
```

### NutanixMachine

The `NutanixMachine` resource represents a single VM on Nutanix AHV that backs a Kubernetes node.

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: NutanixMachine
metadata:
  name: my-cluster-worker-0
  namespace: default
  ownerReferences:
    - apiVersion: cluster.x-k8s.io/v1beta1
      kind: Machine
      name: my-cluster-worker-0
spec:
  # VM specifications
  vcpuSockets: 4
  vcpusPerSocket: 1
  memorySize: "8Gi"
  
  # Boot configuration
  bootType: legacy  # or uefi
  
  # System disk configuration
  systemDiskSize: "100Gi"
  
  # OS Image reference
  image:
    type: name
    name: "ubuntu-22.04-kube-v1.28.0"
    # Alternative: use UUID
    # type: uuid
    # uuid: "abc123-def456..."
  
  # Nutanix cluster (Prism Element) to deploy VM
  cluster:
    type: name
    name: "nutanix-cluster-1"
  
  # Network subnet configuration
  subnet:
    - type: name
      name: "vm-network"
  
  # Optional: Project for RBAC
  project:
    type: name
    name: "kubernetes-project"
  
  # Optional: Categories for organization/policy
  categories:
    - key: "Environment"
      value: "Production"
    - key: "Application"
      value: "Kubernetes"
  
  # Optional: GPU configuration
  gpus: []
  
  # Optional: Additional disks
  additionalCategories: []

status:
  ready: true
  vmUUID: "vm-uuid-12345"
  addresses:
    - type: InternalIP
      address: "10.0.0.15"
  conditions:
    - type: Ready
      status: "True"
```

### NutanixMachineTemplate

The `NutanixMachineTemplate` is used by MachineDeployments and MachineSets to create NutanixMachine instances.

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: NutanixMachineTemplate
metadata:
  name: my-cluster-worker-template
  namespace: default
spec:
  template:
    spec:
      vcpuSockets: 4
      vcpusPerSocket: 1
      memorySize: "8Gi"
      bootType: legacy
      systemDiskSize: "100Gi"
      image:
        type: name
        name: "ubuntu-22.04-kube-v1.28.0"
      cluster:
        type: name
        name: "nutanix-cluster-1"
      subnet:
        - type: name
          name: "vm-network"
      project:
        type: name
        name: "kubernetes-project"
      categories:
        - key: "Environment"
          value: "Production"
```

---

## Object Relationships & References

### Reference Types

CAPI uses several types of references to link objects:

| Reference Type | Description | Example |
|---------------|-------------|---------|
| **infrastructureRef** | Links core objects to infrastructure provider objects | `Cluster.spec.infrastructureRef` → `NutanixCluster` |
| **controlPlaneRef** | Links Cluster to control plane provider | `Cluster.spec.controlPlaneRef` → `KubeadmControlPlane` |
| **bootstrap.configRef** | Links Machine to bootstrap configuration | `Machine.spec.bootstrap.configRef` → `KubeadmConfig` |
| **ownerReferences** | Kubernetes ownership for garbage collection | `NutanixCluster.ownerReferences` → `Cluster` |
| **template references** | Links deployments to templates | `MachineDeployment.spec.template.spec.infrastructureRef` → `NutanixMachineTemplate` |

### Complete Reference Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    OBJECT REFERENCE HIERARCHY                                    │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘

                                         ┌───────────────┐
                                         │    Cluster    │
                                         │ (CAPI Core)   │
                                         └───────┬───────┘
                                                 │
                    ┌────────────────────────────┼────────────────────────────┐
                    │                            │                            │
                    │ spec.infrastructureRef     │ spec.controlPlaneRef       │ ownerReferences
                    ▼                            ▼                            │
           ┌────────────────┐          ┌─────────────────────┐               │
           │ NutanixCluster │          │ KubeadmControlPlane │               │
           │ (Infrastructure│          │   (Control Plane    │               │
           │    Provider)   │          │     Provider)       │               │
           └────────────────┘          └──────────┬──────────┘               │
                    ▲                             │                           │
                    │ ownerRef                    │ spec.machineTemplate      │
                    │                             │   .infrastructureRef      │
                    │                             ▼                           │
                    │                  ┌─────────────────────────┐           │
                    │                  │ NutanixMachineTemplate  │           │
                    │                  │   (CP Template)         │           │
                    │                  └─────────────────────────┘           │
                    │                                                         │
┌───────────────────┼─────────────────────────────────────────────────────────┼───────────────────┐
│                   │                   WORKER POOL HIERARCHY                 │                   │
│                   │                                                         │                   │
│                   │                  ┌───────────────────┐                  │                   │
│                   │                  │ MachineDeployment │◄─────────────────┘                   │
│                   │                  │   (CAPI Core)     │                                      │
│                   │                  └─────────┬─────────┘                                      │
│                   │                            │                                                 │
│                   │         ┌──────────────────┼──────────────────┐                             │
│                   │         │                  │                  │                             │
│                   │         │ spec.template    │ spec.template    │                             │
│                   │         │  .spec.bootstrap │  .spec.infra...  │                             │
│                   │         ▼                  │                  ▼                             │
│                   │  ┌─────────────────┐       │      ┌─────────────────────────┐              │
│                   │  │KubeadmConfig    │       │      │ NutanixMachineTemplate  │              │
│                   │  │   Template      │       │      │   (Worker Template)     │              │
│                   │  └─────────────────┘       │      └─────────────────────────┘              │
│                   │                            │                  │                             │
│                   │                            ▼                  │                             │
│                   │                  ┌───────────────────┐        │                             │
│                   │                  │   MachineSet      │        │                             │
│                   │                  │   (CAPI Core)     │        │                             │
│                   │                  └─────────┬─────────┘        │                             │
│                   │                            │                  │                             │
│                   │                            │ creates          │                             │
│                   │                            ▼                  │                             │
│                   │                  ┌───────────────────┐        │                             │
│                   │                  │     Machine       │        │                             │
│                   │                  │   (CAPI Core)     │        │                             │
│                   │                  └─────────┬─────────┘        │                             │
│                   │                            │                  │                             │
│                   │    ┌───────────────────────┼──────────────────┼────────────────────┐       │
│                   │    │                       │                  │                    │       │
│                   │    │ spec.bootstrap        │ spec.infra...    │ ownerRef          │       │
│                   │    │   .configRef          │   structureRef   │                    │       │
│                   │    ▼                       │                  ▼                    │       │
│                   │  ┌─────────────┐           │         ┌────────────────┐           │       │
│                   │  │KubeadmConfig│           │         │ NutanixMachine │───────────┘       │
│                   │  │ (Bootstrap) │           │         │ (Infrastructure)           │       │
│                   │  └─────────────┘           │         └────────────────┘                   │
│                   │         │                  │                  │                             │
│                   │         │ creates          │                  │ creates                     │
│                   │         ▼                  │                  ▼                             │
│                   │  ┌─────────────┐           │         ┌────────────────┐                    │
│                   │  │   Secret    │           │         │  Nutanix VM    │                    │
│                   │  │ (bootstrap  │           │         │  (Actual VM)   │                    │
│                   │  │   data)     │           │         └────────────────┘                    │
│                   │  └─────────────┘           │                                                │
│                   │                            │                                                │
│                   └────────────────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Owner Reference Chain

```
Cluster
   │
   ├──► NutanixCluster (ownerRef: Cluster)
   │
   ├──► KubeadmControlPlane (ownerRef: Cluster)
   │       │
   │       └──► Machine (ownerRef: KubeadmControlPlane)
   │               │
   │               ├──► NutanixMachine (ownerRef: Machine)
   │               │
   │               └──► KubeadmConfig (ownerRef: Machine)
   │
   └──► MachineDeployment (ownerRef: Cluster)
           │
           └──► MachineSet (ownerRef: MachineDeployment)
                   │
                   └──► Machine (ownerRef: MachineSet)
                           │
                           ├──► NutanixMachine (ownerRef: Machine)
                           │
                           └──► KubeadmConfig (ownerRef: Machine)
```

---

## Block Diagrams

### Complete System Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                      MANAGEMENT CLUSTER                                             │
├────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                                 KUBERNETES API SERVER                                        │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────────────────┐   │   │
│  │  │                              Custom Resource Definitions                             │   │   │
│  │  │                                                                                      │   │   │
│  │  │   cluster.x-k8s.io/v1beta1:                                                         │   │   │
│  │  │   ├── Cluster, Machine, MachineSet, MachineDeployment, ClusterClass                 │   │   │
│  │  │   │                                                                                  │   │   │
│  │  │   controlplane.cluster.x-k8s.io/v1beta1:                                            │   │   │
│  │  │   ├── KubeadmControlPlane                                                           │   │   │
│  │  │   │                                                                                  │   │   │
│  │  │   bootstrap.cluster.x-k8s.io/v1beta1:                                               │   │   │
│  │  │   ├── KubeadmConfig, KubeadmConfigTemplate                                          │   │   │
│  │  │   │                                                                                  │   │   │
│  │  │   infrastructure.cluster.x-k8s.io/v1beta1:                                          │   │   │
│  │  │   └── NutanixCluster, NutanixMachine, NutanixMachineTemplate                        │   │   │
│  │  └─────────────────────────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                              │                                                      │
│                        ┌─────────────────────┼─────────────────────┐                               │
│                        │                     │                     │                               │
│                        ▼                     ▼                     ▼                               │
│  ┌──────────────────────────┐  ┌──────────────────────────┐  ┌──────────────────────────┐        │
│  │     CAPI CORE            │  │   BOOTSTRAP PROVIDER     │  │   CONTROLPLANE PROVIDER  │        │
│  │     CONTROLLERS          │  │      (Kubeadm)           │  │       (Kubeadm)          │        │
│  │  ────────────────────    │  │  ────────────────────    │  │  ────────────────────    │        │
│  │                          │  │                          │  │                          │        │
│  │  Watches & Reconciles:   │  │  Watches & Reconciles:   │  │  Watches & Reconciles:   │        │
│  │  • Cluster              │  │  • KubeadmConfig         │  │  • KubeadmControlPlane   │        │
│  │  • Machine              │  │  • KubeadmConfigTemplate │  │                          │        │
│  │  • MachineSet           │  │                          │  │  Creates:                │        │
│  │  • MachineDeployment    │  │  Creates:                │  │  • Machines for CP       │        │
│  │  • ClusterClass         │  │  • Bootstrap Secrets     │  │  • Certificates          │        │
│  │                          │  │  • cloud-init data      │  │  • Kubeconfig            │        │
│  └────────────┬─────────────┘  └────────────┬─────────────┘  └────────────┬─────────────┘        │
│               │                             │                             │                       │
│               │                             │                             │                       │
│               └─────────────────────────────┼─────────────────────────────┘                       │
│                                             │                                                      │
│                                             ▼                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                          CAPX - NUTANIX INFRASTRUCTURE PROVIDER                             │   │
│  │  ───────────────────────────────────────────────────────────────────────────────────────    │   │
│  │                                                                                              │   │
│  │  ┌───────────────────────────┐  ┌───────────────────────────┐  ┌───────────────────────┐   │   │
│  │  │  NutanixCluster          │  │  NutanixMachine           │  │  NutanixMachineTemplate│   │   │
│  │  │  Controller              │  │  Controller               │  │  Controller            │   │   │
│  │  │  ─────────────────────   │  │  ─────────────────────    │  │  ─────────────────     │   │   │
│  │  │                          │  │                           │  │                        │   │   │
│  │  │  Reconciles:             │  │  Reconciles:              │  │  Reconciles:           │   │   │
│  │  │  • Control plane endpoint│  │  • VM lifecycle           │  │  • Template validation │   │   │
│  │  │  • Prism connection      │  │  • VM creation/deletion   │  │  • Defaults            │   │   │
│  │  │  • Failure domains       │  │  • Network configuration  │  │                        │   │   │
│  │  │                          │  │  • providerID assignment  │  │                        │   │   │
│  │  │  Sets:                   │  │                           │  │                        │   │   │
│  │  │  • status.ready          │  │  Sets:                    │  │                        │   │   │
│  │  │  • status.failureDomains │  │  • status.ready           │  │                        │   │   │
│  │  │                          │  │  • status.vmUUID          │  │                        │   │   │
│  │  │                          │  │  • status.addresses       │  │                        │   │   │
│  │  └───────────┬──────────────┘  └───────────┬───────────────┘  └────────────────────────┘   │   │
│  │              │                             │                                                │   │
│  │              │    Nutanix API Client       │                                                │   │
│  │              │    (Prism Central SDK)      │                                                │   │
│  │              └──────────────┬──────────────┘                                                │   │
│  └─────────────────────────────┼───────────────────────────────────────────────────────────────┘   │
│                                │                                                                    │
└────────────────────────────────┼────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ REST API (HTTPS)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    NUTANIX INFRASTRUCTURE                                            │
├─────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                      │
│  ┌────────────────────────────────────────────────────────────────────────────────────────────┐     │
│  │                              PRISM CENTRAL (PC)                                             │     │
│  │  ─────────────────────────────────────────────────────────────────────────────────────     │     │
│  │  • Centralized Management              • API Gateway (v3, v4 APIs)                         │     │
│  │  • Multi-cluster Management            • Authentication & RBAC                              │     │
│  │  • Categories & Projects               • Image Management                                   │     │
│  └────────────────────────────────────────────────────────────────────────────────────────────┘     │
│                                              │                                                       │
│               ┌──────────────────────────────┼──────────────────────────────┐                       │
│               │                              │                              │                       │
│               ▼                              ▼                              ▼                       │
│  ┌──────────────────────┐      ┌──────────────────────┐      ┌──────────────────────┐             │
│  │   PRISM ELEMENT      │      │   PRISM ELEMENT      │      │   PRISM ELEMENT      │             │
│  │   (Cluster 1)        │      │   (Cluster 2)        │      │   (Cluster N)        │             │
│  │  ────────────────    │      │  ────────────────    │      │  ────────────────    │             │
│  │  • AHV Hypervisor    │      │  • AHV Hypervisor    │      │  • AHV Hypervisor    │             │
│  │  • Storage (DSF)     │      │  • Storage (DSF)     │      │  • Storage (DSF)     │             │
│  │  • Networking (AHV)  │      │  • Networking (AHV)  │      │  • Networking (AHV)  │             │
│  │                      │      │                      │      │                      │             │
│  │  VMs:                │      │  VMs:                │      │  VMs:                │             │
│  │  ┌────┐ ┌────┐      │      │  ┌────┐ ┌────┐      │      │  ┌────┐ ┌────┐      │             │
│  │  │ CP │ │ W1 │ ...  │      │  │ CP │ │ W1 │ ...  │      │  │ CP │ │ W1 │ ...  │             │
│  │  └────┘ └────┘      │      │  └────┘ └────┘      │      │  └────┘ └────┘      │             │
│  └──────────────────────┘      └──────────────────────┘      └──────────────────────┘             │
│                                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Controller Reconciliation Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                            CONTROLLER RECONCILIATION FLOW                                │
└─────────────────────────────────────────────────────────────────────────────────────────┘

User Creates Cluster + MachineDeployment
              │
              ▼
    ┌─────────────────────┐
    │  Cluster Controller │  ◄── Watches: Cluster
    │     (CAPI Core)     │
    └──────────┬──────────┘
               │
               │ 1. Sees Cluster.spec.infrastructureRef
               │    → NutanixCluster
               ▼
    ┌─────────────────────────┐
    │  NutanixCluster         │  ◄── Watches: NutanixCluster
    │  Controller (CAPX)      │
    └──────────┬──────────────┘
               │
               │ 2. Configures Prism Central connection
               │    Sets control plane endpoint
               │    Marks status.ready = true
               ▼
    ┌─────────────────────────┐
    │  Cluster Controller     │
    │  (continues)            │
    └──────────┬──────────────┘
               │
               │ 3. Sees infrastructureReady = true
               │    Processes controlPlaneRef
               ▼
    ┌─────────────────────────────┐
    │  KubeadmControlPlane        │  ◄── Watches: KubeadmControlPlane
    │  Controller                 │
    └──────────┬──────────────────┘
               │
               │ 4. Creates Machines for control plane
               │    Uses machineTemplate.infrastructureRef
               │    → NutanixMachineTemplate
               ▼
    ┌─────────────────────────┐
    │  Machine Controller     │  ◄── Watches: Machine
    │     (CAPI Core)         │
    └──────────┬──────────────┘
               │
               │ 5. Creates NutanixMachine from template
               │    Creates KubeadmConfig for bootstrap
               │
    ┌──────────┴─────────────────────────────┐
    │                                         │
    ▼                                         ▼
┌────────────────────┐             ┌────────────────────────┐
│ KubeadmConfig      │             │ NutanixMachine         │
│ Controller         │             │ Controller (CAPX)      │
│ (Bootstrap)        │             └──────────┬─────────────┘
└──────────┬─────────┘                        │
           │                                   │
           │ 6a. Generates cloud-init         │ 6b. Creates VM via Prism API
           │     Creates bootstrap Secret      │     Configures network, storage
           │     Marks dataSecretName          │     Sets status.vmUUID
           ▼                                   │     Sets status.addresses
    ┌─────────────────┐                       │     Marks status.ready = true
    │ Bootstrap Ready │                       ▼
    └─────────────────┘                ┌─────────────────┐
                                       │ Infrastructure  │
                                       │    Ready        │
                                       └─────────────────┘
           │                                   │
           └─────────────┬─────────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │  Machine Controller │
              │  (continues)        │
              └──────────┬──────────┘
                         │
                         │ 7. Both bootstrapReady and infrastructureReady
                         │    VM boots with cloud-init
                         │    Node joins cluster via kubeadm
                         ▼
              ┌─────────────────────┐
              │   Node Registered   │
              │   in Workload       │
              │   Cluster           │
              └─────────────────────┘
                         │
                         │ 8. Machine.status.nodeRef set
                         │    Machine.status.phase = Running
                         ▼
              ┌─────────────────────┐
              │  Machine Ready      │
              └─────────────────────┘
```

---

## Controller Interfaces & Contracts

### InfraCluster Contract

The `NutanixCluster` must satisfy the **InfraCluster** contract defined by Cluster API:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       InfraCluster Contract                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  REQUIRED:                                                               │
│  ─────────                                                               │
│  • CRD in infrastructure.cluster.x-k8s.io API group                     │
│  • Namespace-scoped resource                                             │
│  • spec.controlPlaneEndpoint (host + port)                              │
│  • status.ready boolean field                                            │
│  • status.failureDomains (optional, for HA)                             │
│                                                                          │
│  OWNERSHIP:                                                              │
│  ──────────                                                              │
│  • Must accept ownerReference from Cluster                              │
│  • Deleted when parent Cluster is deleted                               │
│                                                                          │
│  BEHAVIOR:                                                               │
│  ─────────                                                               │
│  • Set status.ready = true when infrastructure is ready                 │
│  • Cluster controller waits for status.ready before proceeding          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### InfraMachine Contract

The `NutanixMachine` must satisfy the **InfraMachine** contract:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       InfraMachine Contract                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  REQUIRED:                                                               │
│  ─────────                                                               │
│  • CRD in infrastructure.cluster.x-k8s.io API group                     │
│  • Namespace-scoped resource                                             │
│  • spec.providerID (set after VM creation)                              │
│  • status.ready boolean field                                            │
│  • status.addresses (list of node addresses)                            │
│  • status.failureReason / status.failureMessage (for errors)            │
│                                                                          │
│  OPTIONAL:                                                               │
│  ─────────                                                               │
│  • spec.failureDomain (for placement)                                   │
│                                                                          │
│  OWNERSHIP:                                                              │
│  ──────────                                                              │
│  • Must accept ownerReference from Machine                              │
│  • Deleted when parent Machine is deleted                               │
│                                                                          │
│  BEHAVIOR:                                                               │
│  ─────────                                                               │
│  • Create VM when InfraMachine is created                               │
│  • Set spec.providerID to unique VM identifier                          │
│  • Set status.addresses with IP addresses                               │
│  • Set status.ready = true when VM is running                           │
│  • Delete VM when InfraMachine is deleted                               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### InfraMachineTemplate Contract

The `NutanixMachineTemplate` must satisfy the **InfraMachineTemplate** contract:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    InfraMachineTemplate Contract                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  REQUIRED:                                                               │
│  ─────────                                                               │
│  • CRD in infrastructure.cluster.x-k8s.io API group                     │
│  • Namespace-scoped resource                                             │
│  • spec.template.spec containing InfraMachine spec                      │
│                                                                          │
│  USAGE:                                                                  │
│  ──────                                                                  │
│  • Referenced by MachineDeployment, MachineSet, KubeadmControlPlane     │
│  • Used to stamp out individual InfraMachine instances                  │
│  • Template spec is copied to new InfraMachine                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Status Fields Mapping

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           STATUS FIELD PROPAGATION                                   │
└─────────────────────────────────────────────────────────────────────────────────────┘

NutanixCluster.status                     Cluster.status
├── ready: true          ──────────────►  ├── infrastructureReady: true
└── failureDomains: {}   ──────────────►  └── failureDomains: {}


NutanixMachine.status                     Machine.status
├── ready: true          ──────────────►  ├── infrastructureReady: true
├── addresses: [...]     ──────────────►  ├── addresses: [...]
├── vmUUID: "..."                         │
└── failureReason: ""    ──────────────►  └── failureReason: ""


Bootstrap (KubeadmConfig)                 Machine.status
├── ready: true          ──────────────►  ├── bootstrapReady: true
└── dataSecretName       ──────────────►  └── bootstrap.dataSecretName


Machine Controller Logic:
─────────────────────────

IF Machine.status.bootstrapReady == true
   AND Machine.status.infrastructureReady == true
   AND Node exists with matching providerID
THEN
   Machine.status.phase = "Running"
   Machine.status.nodeRef = <Node reference>
```

---

## Reconciliation Flow

### Detailed Sequence Diagram

```
┌──────────┐    ┌─────────────┐    ┌─────────────────┐    ┌──────────────┐    ┌─────────────┐
│  User    │    │   Cluster   │    │  NutanixCluster │    │   Machine    │    │NutanixMachine│
│          │    │  Controller │    │   Controller    │    │  Controller  │    │  Controller │
└────┬─────┘    └──────┬──────┘    └───────┬─────────┘    └──────┬───────┘    └──────┬──────┘
     │                 │                   │                     │                    │
     │ Create Cluster  │                   │                     │                    │
     │ + NutanixCluster│                   │                     │                    │
     │ + KubeadmCP     │                   │                     │                    │
     │─────────────────►                   │                     │                    │
     │                 │                   │                     │                    │
     │                 │ Watch: Cluster    │                     │                    │
     │                 │ detected          │                     │                    │
     │                 │───────────────────►                     │                    │
     │                 │                   │                     │                    │
     │                 │                   │ Reconcile:          │                    │
     │                 │                   │ - Connect to Prism  │                    │
     │                 │                   │ - Set CP endpoint   │                    │
     │                 │                   │ - Set ready=true    │                    │
     │                 │◄──────────────────│                     │                    │
     │                 │ infrastructureReady│                    │                    │
     │                 │                   │                     │                    │
     │                 │ Continue reconcile│                     │                    │
     │                 │ Process controlPlaneRef                 │                    │
     │                 │                   │                     │                    │
     │                 │ Create Machine for CP                   │                    │
     │                 │─────────────────────────────────────────►                    │
     │                 │                   │                     │                    │
     │                 │                   │                     │ Watch: Machine     │
     │                 │                   │                     │ detected           │
     │                 │                   │                     │────────────────────►
     │                 │                   │                     │                    │
     │                 │                   │                     │                    │ Reconcile:
     │                 │                   │                     │                    │ - Call Prism API
     │                 │                   │                     │                    │ - Create VM
     │                 │                   │                     │                    │ - Set vmUUID
     │                 │                   │                     │                    │ - Set addresses
     │                 │                   │                     │                    │ - Set ready=true
     │                 │                   │                     │◄───────────────────│
     │                 │                   │                     │ infrastructureReady│
     │                 │                   │                     │                    │
     │                 │                   │                     │ Continue:          │
     │                 │                   │                     │ - Wait for node    │
     │                 │                   │                     │ - Set nodeRef      │
     │                 │                   │                     │ - phase=Running    │
     │                 │                   │                     │                    │
```

---

## Cloud Controller Manager Integration

### Architecture with Cloud Provider

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              WORKLOAD CLUSTER                                            │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                           CONTROL PLANE                                            │  │
│  │                                                                                    │  │
│  │  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────────────────────┐  │  │
│  │  │  kube-apiserver │   │  kube-scheduler │   │    kube-controller-manager     │  │  │
│  │  │                 │   │                 │   │    (--cloud-provider=external)  │  │  │
│  │  └─────────────────┘   └─────────────────┘   └─────────────────────────────────┘  │  │
│  │                                                                                    │  │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │              cloud-controller-manager (Nutanix)                              │  │  │
│  │  │  ────────────────────────────────────────────────────────────────────────   │  │  │
│  │  │                                                                              │  │  │
│  │  │  Implements cloudprovider.Interface:                                         │  │  │
│  │  │                                                                              │  │  │
│  │  │  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐  │  │  │
│  │  │  │   Node Controller   │  │  Route Controller   │  │ Service Controller  │  │  │  │
│  │  │  │  ─────────────────  │  │  ─────────────────  │  │  ─────────────────  │  │  │  │
│  │  │  │                     │  │                     │  │                     │  │  │  │
│  │  │  │ • Initialize node   │  │ • Configure routes  │  │ • Provision LB      │  │  │  │
│  │  │  │   with providerID   │  │   between pods      │  │   for type:LB       │  │  │  │
│  │  │  │ • Add cloud labels  │  │                     │  │   services          │  │  │  │
│  │  │  │ • Monitor node      │  │                     │  │ • Assign external   │  │  │  │
│  │  │  │   existence         │  │                     │  │   IPs               │  │  │  │
│  │  │  │ • Remove stale      │  │                     │  │                     │  │  │  │
│  │  │  │   nodes             │  │                     │  │                     │  │  │  │
│  │  │  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘  │  │  │
│  │  │                                     │                                        │  │  │
│  │  │                                     │ Nutanix API calls                      │  │  │
│  │  │                                     ▼                                        │  │  │
│  │  │                          ┌─────────────────────┐                             │  │  │
│  │  │                          │  Prism Central API  │                             │  │  │
│  │  │                          │  • VM metadata      │                             │  │  │
│  │  │                          │  • Load Balancers   │                             │  │  │
│  │  │                          │  • Networking       │                             │  │  │
│  │  │                          └─────────────────────┘                             │  │  │
│  │  │                                                                              │  │  │
│  │  └─────────────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                                    │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                          │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                           WORKER NODES                                             │  │
│  │                                                                                    │  │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  kubelet (--cloud-provider=external)                                         │  │  │
│  │  │  ─────────────────────────────────────────────────────────────────────────   │  │  │
│  │  │                                                                              │  │  │
│  │  │  • Registers node with API server                                            │  │  │
│  │  │  • Waits for CCM to initialize node (add providerID, addresses)             │  │  │
│  │  │  • Does NOT set cloud-specific metadata (delegated to CCM)                  │  │  │
│  │  │                                                                              │  │  │
│  │  └─────────────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                                    │  │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  Nutanix CSI Driver                                                          │  │  │
│  │  │  ─────────────────────────────────────────────────────────────────────────   │  │  │
│  │  │                                                                              │  │  │
│  │  │  • Provisions persistent volumes on Nutanix storage                          │  │  │
│  │  │  • Attaches/detaches volumes to VMs                                          │  │  │
│  │  │  • Manages storage classes                                                   │  │  │
│  │  │                                                                              │  │  │
│  │  └─────────────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                                    │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Cloud Provider Interface

The `cloud-provider-nutanix` implements the Kubernetes `cloudprovider.Interface`:

```go
// cloudprovider.Interface (simplified)
type Interface interface {
    // Initialize provides the cloud with a kubernetes client builder
    Initialize(clientBuilder cloudprovider.ControllerClientBuilder, stop <-chan struct{})
    
    // LoadBalancer returns a balancer interface
    LoadBalancer() (cloudprovider.LoadBalancer, bool)
    
    // Instances returns an instances interface
    Instances() (cloudprovider.Instances, bool)
    
    // InstancesV2 returns an instances interface (newer API)
    InstancesV2() (cloudprovider.InstancesV2, bool)
    
    // Zones returns a zones interface
    Zones() (cloudprovider.Zones, bool)
    
    // Routes returns a routes interface
    Routes() (cloudprovider.Routes, bool)
    
    // ProviderName returns the cloud provider ID
    ProviderName() string
    
    // HasClusterID returns true if a ClusterID is required
    HasClusterID() bool
}
```

### ProviderID Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              PROVIDER ID LIFECYCLE                                       │
└─────────────────────────────────────────────────────────────────────────────────────────┘

1. VM Creation (Management Cluster / CAPX)
   ─────────────────────────────────────────
   
   NutanixMachine Controller:
   ├── Creates VM via Prism API
   ├── Receives VM UUID from Prism
   └── Sets NutanixMachine.spec.providerID = "nutanix://<vm-uuid>"

2. Machine Status Update
   ──────────────────────
   
   Machine Controller:
   ├── Reads NutanixMachine.spec.providerID
   └── Copies to Machine.spec.providerID

3. Node Registration (Workload Cluster)
   ─────────────────────────────────────
   
   kubelet:
   ├── Registers Node with API server
   └── Node.spec.providerID is UNSET (external cloud provider)

4. Node Initialization (Cloud Controller Manager)
   ───────────────────────────────────────────────
   
   CCM Node Controller:
   ├── Watches for uninitialized nodes
   ├── Queries Prism API for VM by IP/name
   ├── Sets Node.spec.providerID = "nutanix://<vm-uuid>"
   ├── Adds cloud labels (zone, region, instance-type)
   └── Removes "node.cloudprovider.kubernetes.io/uninitialized" taint

5. Machine-Node Association
   ─────────────────────────
   
   Machine Controller:
   ├── Watches Nodes in workload cluster
   ├── Matches Node.spec.providerID with Machine.spec.providerID
   └── Sets Machine.status.nodeRef to matched Node


ProviderID Format for Nutanix:
──────────────────────────────

nutanix://<prism-central-uuid>/<vm-uuid>

or simplified:

nutanix://<vm-uuid>
```

### CAPX vs Cloud Controller Manager Responsibilities

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                    CAPX vs CLOUD CONTROLLER MANAGER                                      │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  ┌─────────────────────────────────┐     ┌─────────────────────────────────────────────┐│
│  │  CAPX (Management Cluster)      │     │  CCM (Workload Cluster)                     ││
│  │  ─────────────────────────────  │     │  ───────────────────────────────────────    ││
│  │                                 │     │                                              ││
│  │  RESPONSIBILITIES:              │     │  RESPONSIBILITIES:                           ││
│  │                                 │     │                                              ││
│  │  ✓ Create VMs on Nutanix       │     │  ✓ Initialize Nodes with providerID         ││
│  │  ✓ Configure VM resources       │     │  ✓ Add cloud labels to Nodes                ││
│  │  ✓ Assign networks to VMs       │     │  ✓ Remove uninitialized taint               ││
│  │  ✓ Set providerID on Machine   │     │  ✓ Monitor VM existence for node health     ││
│  │  ✓ Delete VMs on scale down    │     │  ✓ Provision LoadBalancer services          ││
│  │  ✓ Handle cluster-level infra   │     │  ✓ Manage cloud routes (if applicable)     ││
│  │                                 │     │                                              ││
│  │  SCOPE:                         │     │  SCOPE:                                      ││
│  │  • Machine lifecycle           │     │  • Node lifecycle (in Kubernetes)            ││
│  │  • Infrastructure provisioning  │     │  • Service LoadBalancer                      ││
│  │                                 │     │  • Cloud-specific node metadata             ││
│  │                                 │     │                                              ││
│  │  RUNS IN:                       │     │  RUNS IN:                                    ││
│  │  • Management cluster          │     │  • Workload cluster control plane            ││
│  │                                 │     │                                              ││
│  └─────────────────────────────────┘     └─────────────────────────────────────────────┘│
│                                                                                          │
│  INTERACTION:                                                                            │
│  ────────────                                                                            │
│                                                                                          │
│  CAPX creates VM with providerID ────► CCM uses providerID to match and manage Node    │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Example YAML Manifests

### Complete Cluster Definition

```yaml
---
# Cluster (Core CAPI)
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-nutanix-cluster
  namespace: default
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["192.168.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
    serviceDomain: cluster.local
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: NutanixCluster
    name: my-nutanix-cluster
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: my-nutanix-cluster-kcp
---
# NutanixCluster (Infrastructure Provider)
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: NutanixCluster
metadata:
  name: my-nutanix-cluster
  namespace: default
spec:
  controlPlaneEndpoint:
    host: "10.0.0.100"
    port: 6443
  prismCentral:
    address: "prism-central.example.com"
    port: 9440
    insecure: false
    credentialRef:
      kind: Secret
      name: nutanix-credentials
---
# KubeadmControlPlane (Control Plane Provider)
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: my-nutanix-cluster-kcp
  namespace: default
spec:
  replicas: 3
  version: v1.28.0
  machineTemplate:
    infrastructureRef:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      kind: NutanixMachineTemplate
      name: my-nutanix-cluster-cp-mt
  kubeadmConfigSpec:
    clusterConfiguration:
      apiServer:
        extraArgs:
          cloud-provider: external
      controllerManager:
        extraArgs:
          cloud-provider: external
    initConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          cloud-provider: external
    joinConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          cloud-provider: external
---
# NutanixMachineTemplate for Control Plane
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: NutanixMachineTemplate
metadata:
  name: my-nutanix-cluster-cp-mt
  namespace: default
spec:
  template:
    spec:
      vcpuSockets: 4
      vcpusPerSocket: 1
      memorySize: "8Gi"
      systemDiskSize: "100Gi"
      bootType: legacy
      image:
        type: name
        name: "ubuntu-22.04-kube-v1.28.0"
      cluster:
        type: name
        name: "nutanix-cluster-1"
      subnet:
        - type: name
          name: "vm-network"
---
# MachineDeployment for Workers
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: my-nutanix-cluster-md-0
  namespace: default
spec:
  clusterName: my-nutanix-cluster
  replicas: 3
  selector:
    matchLabels: {}
  template:
    spec:
      clusterName: my-nutanix-cluster
      version: v1.28.0
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: KubeadmConfigTemplate
          name: my-nutanix-cluster-md-0-kt
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: NutanixMachineTemplate
        name: my-nutanix-cluster-worker-mt
---
# NutanixMachineTemplate for Workers
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: NutanixMachineTemplate
metadata:
  name: my-nutanix-cluster-worker-mt
  namespace: default
spec:
  template:
    spec:
      vcpuSockets: 4
      vcpusPerSocket: 1
      memorySize: "16Gi"
      systemDiskSize: "100Gi"
      bootType: legacy
      image:
        type: name
        name: "ubuntu-22.04-kube-v1.28.0"
      cluster:
        type: name
        name: "nutanix-cluster-1"
      subnet:
        - type: name
          name: "vm-network"
---
# KubeadmConfigTemplate for Workers
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfigTemplate
metadata:
  name: my-nutanix-cluster-md-0-kt
  namespace: default
spec:
  template:
    spec:
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
            cloud-provider: external
---
# Nutanix Credentials Secret
apiVersion: v1
kind: Secret
metadata:
  name: nutanix-credentials
  namespace: default
type: Opaque
stringData:
  credentials: |
    [
      {
        "type": "basic_auth",
        "data": {
          "prismCentral": {
            "username": "admin",
            "password": "your-password"
          }
        }
      }
    ]
```

---

## References

### Official Documentation

- [Cluster API Book](https://cluster-api.sigs.k8s.io/)
- [Cluster API GitHub](https://github.com/kubernetes-sigs/cluster-api)
- [CAPX (Nutanix Provider) GitHub](https://github.com/nutanix-cloud-native/cluster-api-provider-nutanix)
- [CAPX Documentation](https://opendocs.nutanix.com/capx/)
- [Cloud Provider Nutanix](https://github.com/nutanix-cloud-native/cloud-provider-nutanix)
- [Kubernetes Cloud Controller Manager](https://kubernetes.io/docs/concepts/architecture/cloud-controller/)

### API References

- [Cluster API Types](https://doc.crds.dev/github.com/kubernetes-sigs/cluster-api)
- [NutanixCluster Type](https://opendocs.nutanix.com/capx/v1.3.x/types/nutanix_cluster/)
- [NutanixMachineTemplate Type](https://opendocs.nutanix.com/capx/v1.7.x/types/nutanix_machine_template/)

### Provider Contracts

- [InfraCluster Contract](https://cluster-api.sigs.k8s.io/developer/providers/cluster-infrastructure)
- [InfraMachine Contract](https://cluster-api.sigs.k8s.io/developer/providers/machine-infrastructure)

---

## Summary

This document has covered:

1. **Core CAPI Objects**: Cluster, Machine, MachineSet, MachineDeployment, and their roles
2. **Nutanix Provider Objects**: NutanixCluster, NutanixMachine, NutanixMachineTemplate
3. **Object Relationships**: How references and owner references connect objects
4. **Controller Interfaces**: The contracts that infrastructure providers must implement
5. **Reconciliation Flow**: The step-by-step process of cluster and machine creation
6. **Cloud Controller Manager**: How it integrates with CAPX in workload clusters
7. **Example Manifests**: Complete YAML examples for creating a Nutanix-based cluster

The key insight is that CAPI provides a pluggable architecture where:
- **Core controllers** handle generic cluster/machine lifecycle
- **Infrastructure providers (CAPX)** handle Nutanix-specific VM operations
- **Bootstrap providers** handle node initialization (kubeadm)
- **Cloud Controller Manager** handles runtime cloud integration in workload clusters
