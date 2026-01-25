# How vCluster Works: Architecture, Pods, DaemonSets, and Port Conflicts

This document explains how vCluster works, how it handles pods and DaemonSets, and how it resolves port conflicts when multiple vClusters run on the same host cluster.

## Table of Contents
1. [Core Architecture](#core-architecture)
2. [How Pods Are Handled](#how-pods-are-handled)
3. [How DaemonSets Are Handled](#how-daemonsets-are-handled)
4. [Port Conflict Resolution](#port-conflict-resolution)
5. [Networking Isolation](#networking-isolation)

---

## Core Architecture

vCluster creates **fully functional virtual Kubernetes clusters** that run on top of a host Kubernetes cluster. Each vCluster has:

### Components

1. **Virtual API Server**: A real Kubernetes API server running as a pod in the host cluster
   - Provides the Kubernetes API for the virtual cluster
   - Handles all API requests (create pods, services, etc.)
   - Isolated from other vClusters

2. **Syncer Component**: A critical pod that bridges virtual and host clusters
   - **Watches** the virtual cluster API for resource changes
   - **Translates** virtual cluster resources to host cluster resources
   - **Synchronizes** resource status back from host to virtual cluster
   - **Manages** resource lifecycle (create, update, delete)

3. **CoreDNS**: DNS service for the virtual cluster
   - Runs on port **1053** (not privileged port 53) to avoid conflicts
   - Provides DNS resolution within the virtual cluster
   - Each vCluster has its own CoreDNS instance

4. **Namespace Isolation**: Each vCluster runs in its own namespace in the host cluster
   - Example: `vcluster-0001`, `vcluster-0002`, etc.
   - Provides logical separation between virtual clusters

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Host Kubernetes Cluster                   │
│                                                               │
│  ┌──────────────────┐         ┌──────────────────┐          │
│  │  vCluster-0001   │         │  vCluster-0002   │          │
│  │  Namespace       │         │  Namespace       │          │
│  │                  │         │                  │          │
│  │  ┌────────────┐  │         │  ┌────────────┐  │          │
│  │  │ API Server │  │         │  │ API Server │  │          │
│  │  │ Pod        │  │         │  │ Pod        │  │          │
│  │  └────────────┘  │         │  └────────────┘  │          │
│  │                  │         │                  │          │
│  │  ┌────────────┐  │         │  ┌────────────┐  │          │
│  │  │ Syncer Pod │  │         │  │ Syncer Pod │  │          │
│  │  └────────────┘  │         │  └────────────┘  │          │
│  │                  │         │                  │          │
│  │  ┌────────────┐  │         │  ┌────────────┐  │          │
│  │  │ CoreDNS    │  │         │  │ CoreDNS    │  │          │
│  │  │ (port 1053)│  │         │  │ (port 1053)│  │          │
│  │  └────────────┘  │         │  └────────────┘  │          │
│  │                  │         │                  │          │
│  │  ┌────────────┐  │         │  ┌────────────┐  │          │
│  │  │ Your Pods  │  │         │  │ Your Pods  │  │          │
│  │  │ (workloads)│  │         │  │ (workloads)│  │          │
│  │  └────────────┘  │         │  └────────────┘  │          │
│  └──────────────────┘         └──────────────────┘          │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         Host Cluster Nodes (Shared Infrastructure)   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## How Pods Are Handled

### Resource Synchronization Flow

When you create a Pod in a vCluster, here's what happens:

```
1. User creates Pod in vCluster
   kubectl apply -f pod.yaml --context vcluster_vc-0001_...

2. Virtual API Server receives the request
   └─> Pod is stored in virtual cluster's etcd

3. Syncer watches the virtual API
   └─> Detects new Pod resource

4. Syncer translates and creates Pod in host cluster
   └─> Pod is created in host cluster namespace (vcluster-0001)
   └─> Metadata is transformed (labels, annotations added)
   └─> Namespace mapping: vCluster namespace → host namespace

5. Host cluster schedules and runs the Pod
   └─> Pod gets a real IP address in host cluster network
   └─> Pod runs on actual host cluster nodes

6. Syncer syncs status back
   └─> Pod status (Running, Pending, etc.) is synced back to virtual cluster
   └─> Virtual cluster shows the Pod as running
```

### Key Points About Pods

1. **Real Execution**: Pods in vClusters are **real pods** that run in the host cluster, not simulated
2. **Namespace Translation**:
   - Pod in vCluster namespace `default` → Created in host namespace `vcluster-0001`
   - Each vCluster's resources are isolated in its own host namespace
3. **Network Isolation**:
   - Pods get IP addresses from the host cluster's network
   - Pods within the same vCluster can communicate via IP
   - DNS resolution uses the vCluster's CoreDNS (port 1053)
4. **Metadata Transformation**:
   - Syncer adds labels/annotations to identify resources belonging to the vCluster
   - Prevents conflicts and enables proper resource management

### Example: Creating a Pod

```bash
# Connect to vCluster
vcluster connect vc-0001 -n vcluster-0001

# Create a pod in the virtual cluster
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:latest
EOF

# The pod is created in the host cluster namespace vcluster-0001
# But appears in the virtual cluster's default namespace
```

---

## How DaemonSets Are Handled

DaemonSets work similarly to Pods, but with special considerations:

### DaemonSet Synchronization

1. **Virtual DaemonSet Creation**:
   - You create a DaemonSet in the vCluster (e.g., `kubectl apply -f daemonset.yaml`)
   - The virtual API server stores the DaemonSet resource

2. **Syncer Translation**:
   - Syncer watches for DaemonSet resources in the virtual cluster
   - Translates the DaemonSet to the host cluster format
   - Creates the DaemonSet in the host cluster namespace

3. **Pod Scheduling**:
   - The DaemonSet controller in the **host cluster** manages pod creation
   - Pods are scheduled according to the DaemonSet's node selector/affinity rules
   - Each pod runs in the host cluster namespace (e.g., `vcluster-0001`)

4. **Status Synchronization**:
   - Syncer syncs the DaemonSet status back to the virtual cluster
   - Shows how many pods are running, desired, etc.

### Important Considerations for DaemonSets

1. **Node Selection**:
   - DaemonSets in vClusters can use node selectors to target specific nodes
   - This is useful for dedicated node tenancy models (see below)

2. **Host Cluster Control**:
   - The actual DaemonSet controller runs in the host cluster
   - The vCluster's API server provides the interface, but scheduling happens in the host

3. **Isolation**:
   - DaemonSets from different vClusters are isolated by namespace
   - Each vCluster's DaemonSet pods run in their own namespace

### Example: DaemonSet in vCluster

```bash
# Create DaemonSet in vCluster
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: default
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      containers:
      - name: node-exporter
        image: prom/node-exporter:latest
        ports:
        - containerPort: 9100
EOF

# The DaemonSet creates pods in the host cluster namespace
# But they appear as part of the virtual cluster
```

---

## Port Conflict Resolution

This is a critical aspect when running multiple vClusters on the same host cluster.

### Why Port Conflicts Don't Happen

vCluster avoids port conflicts through several mechanisms:

#### 1. **Namespace Isolation**

Each vCluster runs in its own namespace in the host cluster:
- `vcluster-0001` namespace
- `vcluster-0002` namespace
- `vcluster-0003` namespace
- etc.

**Kubernetes Services are namespace-scoped**, so:
- Service `my-app` in vCluster-0001 → `my-app.vcluster-0001.svc.cluster.local`
- Service `my-app` in vCluster-0002 → `my-app.vcluster-0002.svc.cluster.local`

These are **different services** in different namespaces, so no conflict!

#### 2. **CoreDNS Port Selection**

Each vCluster runs its own CoreDNS instance:
- **Port 1053** (non-privileged) instead of port 53
- Prevents permission issues and port conflicts
- Each vCluster's CoreDNS is isolated in its own namespace

#### 3. **Pod Port Conflicts**

Pods from different vClusters can use the same container ports because:
- **Pods are isolated by namespace** in the host cluster
- Pod networking uses the host cluster's CNI (Container Network Interface)
- Each pod gets its own IP address from the host cluster's pod network
- Port conflicts only occur if pods are on the same node and use `hostNetwork: true`

#### 4. **NodePort and LoadBalancer Services**

For services that expose ports on nodes:

- **NodePort Services**:
  - Each service gets a unique NodePort (30000-32767 range)
  - Kubernetes automatically assigns different ports
  - No manual port management needed

- **LoadBalancer Services**:
  - Managed by the host cluster's load balancer
  - Each service gets its own external IP/endpoint

### Tenancy Models for Multiple vClusters

vCluster supports three models for running multiple vClusters on the same host:

#### Model 1: Shared Nodes (Default)

**Multiple vClusters share the same physical nodes**

```
Host Cluster Nodes:
├── Node 1
│   ├── Pods from vCluster-0001
│   ├── Pods from vCluster-0002
│   └── Pods from vCluster-0003
├── Node 2
│   ├── Pods from vCluster-0001
│   └── Pods from vCluster-0002
└── Node 3
    └── Pods from vCluster-0003
```

**Port Conflict Resolution:**
- Pods use different IP addresses (host cluster pod network)
- Services are namespace-scoped (different DNS names)
- No conflicts because of namespace isolation

**Use Case**: Cost-effective, maximum resource utilization

#### Model 2: Dedicated Nodes

**Each vCluster gets exclusive access to specific nodes**

```
Host Cluster Nodes:
├── Node 1, Node 2 (labeled: vcluster=vc-0001)
│   └── Only pods from vCluster-0001
├── Node 3, Node 4 (labeled: vcluster=vc-0002)
│   └── Only pods from vCluster-0002
└── Node 5, Node 6 (labeled: vcluster=vc-0003)
    └── Only pods from vCluster-0003
```

**Port Conflict Resolution:**
- Complete compute separation
- Node selectors ensure pods from different vClusters don't share nodes
- Even if using `hostNetwork: true`, no conflicts because nodes are separate

**Use Case**: Strong isolation, compliance requirements, security boundaries

**Configuration Example:**
```yaml
# vCluster Helm values for dedicated nodes
syncer:
  extraArgs:
    - --node-selector=vcluster=vc-0001
    - --tolerations[0].key=dedicated
    - --tolerations[0].operator=Equal
    - --tolerations[0].value=vc-0001
    - --tolerations[0].effect=NoSchedule
```

#### Model 3: Virtual Nodes (vNode)

**Node boundaries are virtualized for scheduling isolation**

```
Host Cluster Nodes (Physical):
├── Node 1, Node 2, Node 3
│   └── Virtual Nodes:
│       ├── vNode for vCluster-0001
│       ├── vNode for vCluster-0002
│       └── vNode for vCluster-0003
```

**Port Conflict Resolution:**
- Scheduling-level isolation
- Each vCluster sees its own virtual nodes
- Pods can still share physical nodes, but scheduling is isolated
- Uses taints and tolerations for isolation

**Use Case**: Need node-level semantics (taints, tolerations) with shared infrastructure

---

## Networking Isolation

### DNS Isolation

Each vCluster has its own DNS service:

```bash
# In vCluster-0001
kubectl get svc -n kube-system
# Shows: CoreDNS service on port 1053

# In vCluster-0002
kubectl get svc -n kube-system
# Shows: CoreDNS service on port 1053 (different instance, same port)
```

**Why this works:**
- Each CoreDNS runs in its own namespace
- Port 1053 is a container port, not a host port
- No conflicts because they're in different namespaces

### Service DNS Names

Services in vClusters get DNS names scoped to the virtual cluster:

```
# Service in vCluster-0001
my-service.default.svc.cluster.local

# Service in vCluster-0002
my-service.default.svc.cluster.local

# These resolve to different IPs because:
# - vCluster-0001's CoreDNS resolves to services in vcluster-0001 namespace
# - vCluster-0002's CoreDNS resolves to services in vcluster-0002 namespace
```

### Cross-Cluster Communication

If you need pods in one vCluster to access services in another:

1. **Service Mapping**: Configure service mapping in vCluster
2. **External Services**: Use host cluster DNS names
3. **Ingress**: Use host cluster ingress controller

---

## Summary

### How vCluster Works
- Creates virtual Kubernetes clusters with isolated control planes
- Runs API server, syncer, and CoreDNS as pods in host cluster
- Each vCluster is isolated in its own namespace

### Pod Handling
- Pods are **real** and run in the host cluster
- Syncer translates virtual cluster resources to host cluster resources
- Namespace translation ensures isolation
- Status is synced back to virtual cluster

### DaemonSet Handling
- DaemonSets work like Pods but with node-level scheduling
- Host cluster's DaemonSet controller manages pod creation
- Status is synced back to virtual cluster

### Port Conflict Resolution
1. **Namespace isolation**: Services are namespace-scoped (different DNS names)
2. **CoreDNS on port 1053**: Non-privileged port, one per namespace
3. **Pod networking**: Each pod gets unique IP from host cluster network
4. **Tenancy models**: Shared nodes, dedicated nodes, or virtual nodes
5. **NodePort services**: Kubernetes automatically assigns unique ports

### Key Takeaway

**Port conflicts are avoided because:**
- Each vCluster runs in its own namespace
- Kubernetes resources (Services, Pods) are namespace-scoped
- Each vCluster has its own DNS service
- Pod networking uses the host cluster's CNI (unique IPs per pod)

Multiple vClusters can safely run on the same host cluster without port conflicts!

---

## References

- [vCluster Architecture Documentation](https://www.vcluster.com/docs/vcluster/introduction/architecture)
- [vCluster Networking Documentation](https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/networking)
- [vCluster Advanced Networking](https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/networking/advanced)
- [vCluster Isolated Workloads](https://www.vcluster.com/docs/vcluster/deploy/topologies/isolated-workloads)
- [vCluster CoreDNS Configuration](https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/control-plane/components/coredns)
