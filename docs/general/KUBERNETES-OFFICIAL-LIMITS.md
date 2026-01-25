# Kubernetes Official Resource Limits

This document provides a comprehensive reference to the official Kubernetes resource limits as defined in the Kubernetes documentation. All limits and information are sourced from official Kubernetes documentation with direct references.

## Table of Contents

- [Cluster-Level Limits](#cluster-level-limits)
- [Node-Level Limits](#node-level-limits)
- [Resource Types](#resource-types)
- [Resource Management Mechanisms](#resource-management-mechanisms)
- [Namespace-Level Controls](#namespace-level-controls)
- [API Object Limits](#api-object-limits)
- [References](#references)

---

## Cluster-Level Limits

Kubernetes officially supports clusters with the following maximum limits:

| Resource | Maximum Limit | Reference |
|----------|---------------|-----------|
| **Nodes per cluster** | 5,000 nodes | [Large Cluster Considerations](https://kubernetes.io/docs/setup/best-practices/cluster-large/) |
| **Total pods per cluster** | 150,000 pods | [Large Cluster Considerations](https://kubernetes.io/docs/setup/best-practices/cluster-large/) |
| **Total containers per cluster** | 300,000 containers | [Large Cluster Considerations](https://kubernetes.io/docs/setup/best-practices/cluster-large/) |

**Official Documentation Reference:**
- [Considerations for large clusters](https://kubernetes.io/docs/setup/best-practices/cluster-large/)

> **Note:** These limits are tested and supported by Kubernetes. Exceeding these limits may result in degraded performance or instability.

---

## Node-Level Limits

| Resource | Maximum Limit | Reference |
|----------|---------------|-----------|
| **Pods per node** | 110 pods | [Large Cluster Considerations](https://kubernetes.io/docs/setup/best-practices/cluster-large/) |

**Official Documentation Reference:**
- [Considerations for large clusters](https://kubernetes.io/docs/setup/best-practices/cluster-large/)

> **Note:** The default maximum pods per node is 110, but this can be configured via the `--max-pods` flag in the kubelet. The actual limit depends on the node's resources and the pod density requirements.

---

## Resource Types

Kubernetes supports the following resource types for pods and containers:

### CPU
- **Unit:** Kubernetes CPU units (1 CPU = 1000m = 1 vCPU/core)
- **Specification:** Can be specified as integers (e.g., `2`) or millicores (e.g., `500m`)
- **Reference:** [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

### Memory (RAM)
- **Unit:** Bytes (can use suffixes: `Ki`, `Mi`, `Gi`, `Ti`, `Pi`, `Ei`)
- **Examples:** `128Mi`, `2Gi`, `500M`
- **Reference:** [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

### Huge Pages
- **Type:** Linux-specific feature for larger memory page allocations
- **Format:** `hugepages-<size>` (e.g., `hugepages-2Mi`, `hugepages-1Gi`)
- **Reference:** [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

### Ephemeral Storage
- **Unit:** Bytes (can use suffixes: `Ki`, `Mi`, `Gi`, `Ti`, `Pi`, `Ei`)
- **Usage:** Local ephemeral storage for containers and emptyDir volumes
- **Reference:** [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

---

## Resource Management Mechanisms

### Requests and Limits

Kubernetes uses two key concepts for resource management:

#### Requests
- **Purpose:** Amount of resources guaranteed to a container
- **Usage:** Used by the kube-scheduler to determine which node can accommodate the pod
- **Behavior:** The kubelet reserves this amount of resources for the container
- **Reference:** [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

#### Limits
- **Purpose:** Maximum amount of resources a container can use
- **Enforcement:**
  - **CPU limits:** Hard limits enforced by the kernel via CPU throttling
  - **Memory limits:** Reactive enforcement via out-of-memory (OOM) kills
- **Reference:** [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

**Key Points:**
- CPU and memory limits cannot be overcommitted (unlike huge pages)
- If a container exceeds its memory limit, it may be terminated
- If a container exceeds its CPU limit, it will be throttled

---

## Namespace-Level Controls

### Resource Quotas

ResourceQuota objects constrain aggregate resource consumption per namespace and limit the quantity of objects that can be created.

#### Resource Quota Capabilities

ResourceQuotas can limit:

1. **Compute Resources:**
   - `requests.cpu` - Total CPU requests
   - `requests.memory` - Total memory requests
   - `limits.cpu` - Total CPU limits
   - `limits.memory` - Total memory limits
   - `requests.storage` - Total storage requests
   - `persistentvolumeclaims` - Number of PVCs
   - `requests.ephemeral-storage` - Total ephemeral storage requests
   - `limits.ephemeral-storage` - Total ephemeral storage limits

2. **Object Count Quotas:**
   - `pods` - Number of pods
   - `services` - Number of services
   - `replicationcontrollers` - Number of ReplicationControllers
   - `resourcequotas` - Number of ResourceQuotas
   - `secrets` - Number of secrets
   - `configmaps` - Number of ConfigMaps
   - `persistentvolumeclaims` - Number of PVCs
   - `services.nodeports` - Number of NodePort services
   - `services.loadbalancers` - Number of LoadBalancer services

**Important Notes:**
- When a ResourceQuota is enforced for CPU or memory, every new pod in that namespace must specify either requests or limits for those resources
- Deployment creation succeeds even if pods cannot be scheduled due to quota constraints
- Quota violations result in HTTP 403 Forbidden responses

**Official Documentation Reference:**
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Configure a Pod Quota for a Namespace](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/quota-pod-namespace/)

### Limit Ranges

LimitRange policies enforce minimum and maximum resource allocations per pod or container within a namespace.

#### LimitRange Capabilities

LimitRanges can enforce:

1. **Compute Resource Constraints:**
   - Minimum and maximum CPU per pod or container
   - Minimum and maximum memory per pod or container
   - Default CPU request/limit per container
   - Default memory request/limit per container
   - Default CPU request/limit per pod
   - Default memory request/limit per pod

2. **Storage Constraints:**
   - Minimum and maximum storage requests per PersistentVolumeClaim

3. **Ratio Constraints:**
   - Request-to-limit ratios for CPU
   - Request-to-limit ratios for memory

**Enforcement:**
- Limits are enforced at pod admission time
- Resources that violate limits are rejected with HTTP 403 Forbidden
- Default values are applied if not specified

**Official Documentation Reference:**
- [Limit Ranges](https://kubernetes.io/docs/concepts/policy/limit-range/)

---

## API Object Limits

### Default Limits

Kubernetes does not specify absolute hard limits for most API objects (deployments, services, configmaps, etc.) at the cluster level. Instead, limits are typically enforced through:

1. **Resource Quotas** - Per-namespace object count limits
2. **API Server Configuration** - Rate limiting and request size limits
3. **etcd Performance** - Practical limits based on etcd cluster size and performance

### Practical Considerations

While not hard limits, the following are practical considerations for API objects:

- **API Server Rate Limiting:** Default rate limits are configured in the API server
- **etcd Size Limits:** etcd has practical limits based on:
  - Maximum request size (default: 1.5MB)
  - Database size (recommended: < 8GB)
  - Watch event throughput
- **Object Size Limits:** Individual objects should not exceed etcd's maximum request size

**Reference:**
- [API Server Rate Limiting](https://kubernetes.io/docs/reference/config-api/apiserver-config.v1alpha1/)
- [etcd Performance](https://etcd.io/docs/latest/op-guide/performance/)

---

## Summary Table

| Category | Limit | Type | Reference |
|----------|-------|------|-----------|
| **Cluster** | | | |
| Nodes per cluster | 5,000 | Hard limit | [Large Clusters](https://kubernetes.io/docs/setup/best-practices/cluster-large/) |
| Total pods per cluster | 150,000 | Hard limit | [Large Clusters](https://kubernetes.io/docs/setup/best-practices/cluster-large/) |
| Total containers per cluster | 300,000 | Hard limit | [Large Clusters](https://kubernetes.io/docs/setup/best-practices/cluster-large/) |
| **Node** | | | |
| Pods per node | 110 | Default limit | [Large Clusters](https://kubernetes.io/docs/setup/best-practices/cluster-large/) |
| **Resources** | | | |
| CPU | Configurable | Request/Limit | [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) |
| Memory | Configurable | Request/Limit | [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) |
| Ephemeral Storage | Configurable | Request/Limit | [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) |
| **Namespace** | | | |
| Object counts | Configurable via ResourceQuota | Per namespace | [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/) |
| Resource requests/limits | Configurable via ResourceQuota | Per namespace | [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/) |

---

## References

### Official Kubernetes Documentation

1. **Cluster-Level Limits:**
   - [Considerations for large clusters](https://kubernetes.io/docs/setup/best-practices/cluster-large/)

2. **Resource Management:**
   - [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
   - [Manage Memory, CPU, and API Resources](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/)

3. **Namespace-Level Controls:**
   - [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
   - [Limit Ranges](https://kubernetes.io/docs/concepts/policy/limit-range/)
   - [Configure a Pod Quota for a Namespace](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/quota-pod-namespace/)

4. **API Server Configuration:**
   - [API Server Configuration](https://kubernetes.io/docs/reference/config-api/apiserver-config.v1alpha1/)

### Additional Resources

- [Kubernetes API Reference](https://kubernetes.io/docs/reference/kubernetes-api/)
- [etcd Performance Guidelines](https://etcd.io/docs/latest/op-guide/performance/)

---

## Version Information

This document is based on Kubernetes documentation as of 2024. The limits mentioned are applicable to Kubernetes v1.30 and later versions. For the most up-to-date information, always refer to the official Kubernetes documentation.

**Last Updated:** 2024

---

## Notes

1. **Hard Limits vs. Practical Limits:** The cluster-level limits (5,000 nodes, 150,000 pods, etc.) are tested and supported limits. Exceeding these may cause performance degradation or instability.

2. **Configurable Limits:** Many limits (pods per node, resource quotas, etc.) can be configured based on your cluster's requirements and infrastructure capabilities.

3. **Namespace Isolation:** Resource Quotas and Limit Ranges provide namespace-level isolation and control, allowing administrators to enforce limits per namespace rather than cluster-wide.

4. **Best Practices:** When designing large-scale Kubernetes deployments, consider:
   - Using Resource Quotas to prevent resource exhaustion
   - Implementing Limit Ranges to enforce resource policies
   - Monitoring cluster metrics to ensure you stay within supported limits
   - Testing at scale before production deployment
