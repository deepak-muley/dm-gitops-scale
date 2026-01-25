# How vCluster Handles Cluster-Scoped Resources Isolation

This document explains how vCluster isolates cluster-scoped resources across multiple virtual clusters running on the same host cluster.

## Table of Contents
1. [Understanding Cluster-Scoped Resources](#understanding-cluster-scoped-resources)
2. [Isolation Mechanism](#isolation-mechanism)
3. [How Different Resource Types Are Handled](#how-different-resource-types-are-handled)
4. [Comparison: Namespaced vs Cluster-Scoped](#comparison-namespaced-vs-cluster-scoped)
5. [Examples and Use Cases](#examples-and-use-cases)
6. [Important Considerations](#important-considerations)

---

## Understanding Cluster-Scoped Resources

### What Are Cluster-Scoped Resources?

Cluster-scoped resources in Kubernetes are resources that **do not belong to any namespace**. They exist at the cluster level and are accessible from all namespaces. Examples include:

- **ClusterRole** - Cluster-wide RBAC permissions
- **ClusterRoleBinding** - Binds subjects to ClusterRoles
- **PersistentVolume (PV)** - Cluster-wide storage volumes
- **StorageClass** - Defines storage provisioners
- **CustomResourceDefinition (CRD)** - Defines custom resources
- **Node** - Physical/virtual nodes (read-only in vCluster)
- **Namespace** - Namespace objects themselves
- **APIService** - Extended API server definitions
- **MutatingWebhookConfiguration** - Admission webhooks
- **ValidatingWebhookConfiguration** - Validation webhooks
- **ClusterIssuer** (cert-manager) - Cluster-wide certificate issuers
- And many more...

### The Challenge

Unlike namespaced resources (Pods, Services, Deployments) which can be isolated by placing them in different namespaces in the host cluster, **cluster-scoped resources don't have namespaces**. This creates a challenge: How can multiple vClusters on the same host cluster have their own ClusterRoles, StorageClasses, etc., without conflicts?

---

## Isolation Mechanism

### Key Principle: Virtual API Server Isolation

The answer lies in vCluster's architecture: **Each vCluster has its own isolated API server with its own etcd storage**.

```
┌─────────────────────────────────────────────────────────────┐
│                    Host Kubernetes Cluster                   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  vCluster-0001 Namespace                              │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  Virtual API Server Pod                        │  │   │
│  │  │  ┌──────────────────────────────────────────┐  │  │   │
│  │  │  │  etcd (vCluster-0001's storage)          │  │  │   │
│  │  │  │  - ClusterRoles                            │  │  │   │
│  │  │  │  - ClusterRoleBindings                     │  │  │   │
│  │  │  │  - StorageClasses                          │  │  │   │
│  │  │  │  - CRDs                                    │  │  │   │
│  │  │  │  - Namespaces (virtual)                    │  │  │   │
│  │  │  │  - All cluster-scoped resources           │  │  │   │
│  │  │  └──────────────────────────────────────────┘  │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  Syncer Pod                                     │  │   │
│  │  │  (Only syncs namespaced resources)             │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  vCluster-0002 Namespace                              │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  Virtual API Server Pod                        │  │   │
│  │  │  ┌──────────────────────────────────────────┐  │  │   │
│  │  │  │  etcd (vCluster-0002's storage)          │  │  │   │
│  │  │  │  - ClusterRoles (different from vc-0001) │  │  │   │
│  │  │  │  - ClusterRoleBindings                   │  │  │   │
│  │  │  │  - StorageClasses                         │  │  │   │
│  │  │  │  - CRDs                                   │  │  │   │
│  │  │  │  - Namespaces (virtual)                   │  │  │   │
│  │  │  │  - All cluster-scoped resources          │  │  │   │
│  │  │  └──────────────────────────────────────────┘  │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  Syncer Pod                                     │  │   │
│  │  │  (Only syncs namespaced resources)             │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### How It Works

1. **Virtual API Server Storage**: Each vCluster's API server maintains its own etcd instance (or uses a storage backend) where **all cluster-scoped resources are stored**.

2. **No Syncing to Host**: Unlike namespaced resources (Pods, Services), **cluster-scoped resources are NOT synced to the host cluster**. They exist only in the virtual cluster's API server storage.

3. **Complete Isolation**: Since each vCluster has its own API server with its own storage, cluster-scoped resources are completely isolated:
   - vCluster-0001 can have a ClusterRole named `admin`
   - vCluster-0002 can also have a ClusterRole named `admin`
   - They are **different resources** in different API servers
   - No conflicts occur

4. **API Server Acts as Gatekeeper**: When you query cluster-scoped resources in a vCluster, you're querying that vCluster's API server, which returns only resources stored in its own etcd.

---

## How Different Resource Types Are Handled

### 1. ClusterRole and ClusterRoleBinding

**Isolation**: Complete - each vCluster has its own ClusterRoles and ClusterRoleBindings.

```bash
# In vCluster-0001
kubectl --context vcluster_vc-0001_... get clusterrole admin
# Returns: ClusterRole from vCluster-0001's API server

# In vCluster-0002
kubectl --context vcluster_vc-0002_... get clusterrole admin
# Returns: ClusterRole from vCluster-0002's API server (different resource)
```

**How it works**:
- ClusterRoles are stored in each vCluster's API server etcd
- RBAC evaluation happens in the virtual API server
- No syncing to host cluster
- Each vCluster can have completely different RBAC policies

**Example**:
```yaml
# Create ClusterRole in vCluster-0001
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]

# This ClusterRole exists ONLY in vCluster-0001's API server
# vCluster-0002 cannot see it, and vice versa
```

### 2. StorageClass

**Isolation**: Complete - each vCluster can define its own StorageClasses.

```bash
# In vCluster-0001
kubectl --context vcluster_vc-0001_... get storageclass
# Shows StorageClasses defined in vCluster-0001

# In vCluster-0002
kubectl --context vcluster_vc-0002_... get storageclass
# Shows StorageClasses defined in vCluster-0002 (may be different)
```

**Important Note**:
- StorageClasses in vCluster are **virtual definitions**
- When a Pod requests a PVC, the syncer translates it to the host cluster
- The host cluster's StorageClasses are used for actual provisioning
- vCluster StorageClasses act as a mapping/abstraction layer

**How it works**:
1. You define a StorageClass in vCluster (e.g., `fast-ssd`)
2. When a Pod requests a PVC using this StorageClass, the syncer creates the PVC in the host cluster
3. The syncer can map the vCluster StorageClass to a host cluster StorageClass
4. The host cluster provisions the actual storage

### 3. PersistentVolume (PV)

**Isolation**: Complete - each vCluster manages its own PVs (virtually).

**How it works**:
- PVs are cluster-scoped resources stored in the vCluster's API server
- When a PVC is created in a vCluster, the syncer creates a corresponding PVC in the host cluster
- The host cluster's storage provisioner creates the actual PV
- The vCluster sees the PV as bound to the PVC (status synced back)

**Note**: The actual storage is provisioned by the host cluster, but the PV object exists in the vCluster's API server.

### 4. CustomResourceDefinition (CRD)

**Isolation**: Complete - each vCluster can have its own CRDs.

```bash
# Install a CRD in vCluster-0001
kubectl --context vcluster_vc-0001_... apply -f my-crd.yaml

# This CRD exists ONLY in vCluster-0001
# vCluster-0002 cannot see it or use it
```

**How it works**:
- CRDs are stored in each vCluster's API server
- Each vCluster can have completely different custom resources
- CRDs in one vCluster don't affect other vClusters
- This allows different vClusters to use different operators/controllers

**Example Use Case**:
- vCluster-0001: Has ArgoCD CRDs (Application, AppProject)
- vCluster-0002: Has Flux CRDs (GitRepository, Kustomization)
- vCluster-0003: Has both
- No conflicts because each vCluster has its own API server

### 5. Namespace (as a Resource)

**Isolation**: Complete - each vCluster manages its own namespaces.

**Important**: This is a special case!

```bash
# Create namespace in vCluster-0001
kubectl --context vcluster_vc-0001_... create namespace my-app

# This namespace exists ONLY in vCluster-0001's API server
# It does NOT create a namespace in the host cluster
# Pods in this namespace are created in host namespace: vcluster-0001
```

**How it works**:
- Namespaces in vCluster are **virtual** - they exist only in the vCluster's API server
- When you create a Pod in namespace `my-app` in vCluster-0001:
  - The Pod is created in host namespace `vcluster-0001` (not `my-app`)
  - The syncer adds labels/annotations to map the virtual namespace
  - The vCluster API server shows the Pod in namespace `my-app`
  - The host cluster shows the Pod in namespace `vcluster-0001`

### 6. Node Resources

**Isolation**: Shared (with virtualization)

**How it works**:
- Nodes are cluster-scoped resources
- vCluster can show virtual nodes or map to host cluster nodes
- Each vCluster can have its own node view:
  - **Virtual Nodes**: vCluster creates virtual node objects
  - **Host Node Mapping**: vCluster shows host cluster nodes (read-only)
  - **Dedicated Nodes**: vCluster only shows nodes assigned to it (via node selectors)

**Example**:
```bash
# In vCluster-0001 (with dedicated nodes)
kubectl --context vcluster_vc-0001_... get nodes
# Shows only nodes labeled for vCluster-0001

# In vCluster-0002 (with dedicated nodes)
kubectl --context vcluster_vc-0002_... get nodes
# Shows only nodes labeled for vCluster-0002
```

### 7. Webhook Configurations

**Isolation**: Complete - each vCluster can have its own admission webhooks.

**How it works**:
- MutatingWebhookConfiguration and ValidatingWebhookConfiguration are stored in each vCluster's API server
- Webhooks are evaluated by the vCluster's API server
- Each vCluster can have different admission policies
- No conflicts between vClusters

---

## Comparison: Namespaced vs Cluster-Scoped

### Namespaced Resources (Synced to Host)

| Resource Type | Stored In | Synced to Host? | Isolation Method |
|--------------|-----------|-----------------|------------------|
| Pod | vCluster API server + Host cluster | ✅ Yes | Host namespace isolation |
| Service | vCluster API server + Host cluster | ✅ Yes | Host namespace isolation |
| Deployment | vCluster API server + Host cluster | ✅ Yes | Host namespace isolation |
| ConfigMap | vCluster API server + Host cluster | ✅ Yes | Host namespace isolation |
| Secret | vCluster API server + Host cluster | ✅ Yes | Host namespace isolation |

**Flow**:
```
vCluster API Server (stores resource)
    ↓
Syncer watches and translates
    ↓
Host Cluster (creates actual resource in vCluster namespace)
    ↓
Status synced back to vCluster
```

### Cluster-Scoped Resources (NOT Synced)

| Resource Type | Stored In | Synced to Host? | Isolation Method |
|--------------|-----------|-----------------|------------------|
| ClusterRole | vCluster API server only | ❌ No | Separate API server storage |
| ClusterRoleBinding | vCluster API server only | ❌ No | Separate API server storage |
| StorageClass | vCluster API server only | ❌ No | Separate API server storage |
| CRD | vCluster API server only | ❌ No | Separate API server storage |
| Namespace (virtual) | vCluster API server only | ❌ No | Separate API server storage |
| PersistentVolume | vCluster API server only | ❌ No | Separate API server storage |

**Flow**:
```
vCluster API Server (stores resource in its own etcd)
    ↓
NOT synced to host cluster
    ↓
Exists only in virtual cluster
    ↓
Complete isolation per vCluster
```

---

## Examples and Use Cases

### Example 1: Different RBAC Policies Per vCluster

```bash
# vCluster-0001: Strict RBAC
kubectl --context vcluster_vc-0001_... apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list"]
EOF

# vCluster-0002: Permissive RBAC
kubectl --context vcluster_vc-0002_... apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
EOF

# Both vClusters have a ClusterRole named "developer"
# But they have different rules - no conflict!
```

### Example 2: Different Storage Classes Per vCluster

```bash
# vCluster-0001: Fast SSD storage
kubectl --context vcluster_vc-0001_... apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp3
  iops: "3000"
EOF

# vCluster-0002: Standard storage
kubectl --context vcluster_vc-0002_... apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
EOF

# Same name, different configurations - no conflict!
```

### Example 3: Different Operators/CRDs Per vCluster

```bash
# vCluster-0001: Install ArgoCD
kubectl --context vcluster_vc-0001_... apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# vCluster-0002: Install Flux
kubectl --context vcluster_vc-0002_... apply -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml

# Each vCluster has its own CRDs - no conflicts!
```

### Example 4: Virtual Namespaces

```bash
# Create namespaces in different vClusters
kubectl --context vcluster_vc-0001_... create namespace production
kubectl --context vcluster_vc-0002_... create namespace production

# Both vClusters have a "production" namespace
# But in the host cluster:
# - vCluster-0001's pods go to host namespace: vcluster-0001
# - vCluster-0002's pods go to host namespace: vcluster-0002
# No namespace conflicts in host cluster!
```

---

## Important Considerations

### 1. Storage Provisioning

**Important**: While StorageClasses are isolated in vClusters, actual storage provisioning happens in the host cluster.

- vCluster StorageClasses are virtual definitions
- When a PVC is created, the syncer creates it in the host cluster
- The host cluster's storage provisioner handles actual provisioning
- You may need to configure StorageClass mapping in syncer configuration

### 2. Node Resources

- Nodes can be shared or dedicated per vCluster
- Use node selectors to dedicate nodes to specific vClusters
- Virtual nodes provide scheduling isolation while sharing infrastructure

### 3. CRD Compatibility

- CRDs installed in a vCluster are isolated to that vCluster
- If you need the same CRDs in multiple vClusters, install them in each
- Operators/controllers need to be installed per vCluster

### 4. Webhook Limitations

- Admission webhooks in vCluster are evaluated by the vCluster's API server
- They don't affect the host cluster
- Host cluster webhooks don't affect vCluster resources (namespaced resources are synced, but webhooks run in host)

### 5. Resource Quotas

- ResourceQuota is a namespaced resource, so it's synced to the host cluster
- ClusterResourceQuota (if supported) would be cluster-scoped and isolated per vCluster

### 6. API Server Storage

- Each vCluster's API server needs storage for its etcd
- This can be a PersistentVolume in the host cluster
- Storage requirements depend on the number of cluster-scoped resources

---

## Summary

### Key Points

1. **Complete Isolation**: Cluster-scoped resources are stored in each vCluster's own API server etcd, providing complete isolation.

2. **No Syncing**: Unlike namespaced resources, cluster-scoped resources are NOT synced to the host cluster.

3. **Separate API Servers**: Each vCluster has its own API server with its own storage, so resources with the same name in different vClusters are different resources.

4. **Virtual vs Real**:
   - Cluster-scoped resources in vCluster are "virtual" (exist only in vCluster's API server)
   - Namespaced resources are "real" (synced to host cluster and actually run there)

5. **No Conflicts**: Multiple vClusters can have ClusterRoles, StorageClasses, CRDs, etc., with the same names without any conflicts.

### Isolation Comparison

| Aspect | Namespaced Resources | Cluster-Scoped Resources |
|--------|---------------------|-------------------------|
| **Storage** | vCluster API server + Host cluster | vCluster API server only |
| **Isolation** | Host namespace | Separate API server storage |
| **Syncing** | ✅ Yes (via syncer) | ❌ No |
| **Conflicts** | Avoided via namespace isolation | Avoided via separate API servers |
| **Examples** | Pods, Services, Deployments | ClusterRole, StorageClass, CRD |

### The Bottom Line

**Cluster-scoped resources are isolated because each vCluster has its own isolated API server with its own etcd storage. Resources stored in one vCluster's API server are completely separate from resources in another vCluster's API server, even if they have the same name.**

This architecture allows multiple vClusters to coexist on the same host cluster with complete isolation of both namespaced and cluster-scoped resources!

---

## References

- [vCluster Architecture Documentation](https://www.vcluster.com/docs/vcluster/introduction/architecture)
- [vCluster Resource Synchronization](https://www.vcluster.com/docs/vcluster/introduction/architecture#resource-synchronization)
- [vCluster Storage Configuration](https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/storage)
