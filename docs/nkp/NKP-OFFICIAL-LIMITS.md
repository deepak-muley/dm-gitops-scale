# Nutanix Kubernetes Platform (NKP) 2.17 Official Limits

This document provides a comprehensive reference to the official Nutanix Kubernetes Platform (NKP) resource limits, constraints, and boundaries as defined in the NKP 2.17 User Guide. All limits and information are sourced from the official NKP 2.17 documentation with direct page references.

> **Reference Documentation:** Nutanix Kubernetes Platform v2.17 User Guide (`~/Downloads/Nutanix-Kubernetes-Platform-v2_17.pdf`)
>
> **Last Updated:** January 2026

## Table of Contents

- [Control Plane and Worker Node Resource Requirements](#control-plane-and-worker-node-resource-requirements)
- [Edition-Specific Minimum Requirements](#edition-specific-minimum-requirements)
- [Storage Requirements](#storage-requirements)
- [Platform Application Resource Requirements](#platform-application-resource-requirements)
- [Known Limitations](#known-limitations)
- [Configuration Maximums](#configuration-maximums)
- [Infrastructure Provider Requirements](#infrastructure-provider-requirements)
- [References](#references)

---

## Control Plane and Worker Node Resource Requirements

### Production Deployment Minimums

For production deployments, NKP requires:

| Component | Minimum Requirement | Reference |
|-----------|---------------------|----------|
| **Control Plane Nodes** | At least 3 nodes | Page 795, 843 |
| **Worker Nodes** | Minimum of 4 nodes | Page 795, 843 |

**Official Documentation Reference:**
- Page 795: Control Plane Nodes and Worker Nodes Resource Requirements for Nutanix Kubernetes Platform
- Page 843: Machine Specifications

> **Note:** The exact number of worker nodes required for your environment might vary depending on the workload of your cluster and the size of the nodes. (Page 795)

> **Caution:** You can create a working NKP management cluster with a single control plane node. However, if the single control plane node faces corruption or failure, it results in the loss of the entire cluster. (Page 797)

---

## Edition-Specific Minimum Requirements

### Starter Edition Requirements

**Management Cluster Minimum Requirements:**

| Resource | Control Plane Node | Worker Node | Reference |
|----------|-------------------|-------------|-----------|
| **Minimum node requirements** | 3 | 2 | Page 796, Table 65 |
| **vCPU count** | 2 | 4 | Page 796, Table 65 |
| **Memory** | 8 GiB | 8 GiB | Page 796, Table 65 |
| **Disk volume** | Approximately 80 GiB (for /var/lib/kubelet and /var/lib/containerd) | Approximately 80 GiB (for /var/lib/kubelet and /var/lib/containerd) | Page 796, Table 65 |
| **Root volume** | Disk usage must be below 85% | Disk usage must be below 85% | Page 796, Table 65 |

**Managed Cluster Minimum Requirements:**

| Resource | Control Plane Node | Worker Node | Reference |
|----------|-------------------|-------------|-----------|
| **Minimum node requirements** | 3 | 2 | Page 796, Table 66 |
| **vCPU count** | 2 | 3 | Page 796, Table 66 |
| **Memory** | 6 GiB | 6 GiB | Page 796, Table 66 |
| **Disk volume** | Approximately 80 GiB (for /var/lib/kubelet and /var/lib/containerd) | Approximately 80 GiB (for /var/lib/kubelet and /var/lib/containerd) | Page 796, Table 66 |
| **Root volume** | Disk usage must be below 85% | Disk usage must be below 85% | Page 796, Table 66 |

**Important Notes:**
- The Starter license is supported exclusively with the Nutanix infrastructure. (Page 796)
- If you have two worker nodes in your Starter NKP management and managed clusters and you apply for a Pro or Ultimate license, the additional Pro or Ultimate features fail because your environment does not have enough cluster resources to deploy them. (Page 796)

**Official Documentation Reference:**
- Page 796: Table 65 - Resource Requirements for Management Cluster
- Page 796: Table 66 - Resource Requirements for Managed Cluster

### Pro and Ultimate Edition Requirements

**Management Cluster Minimum Requirements:**

| Resource | Control Plane Node | Worker Node | Reference |
|----------|-------------------|-------------|-----------|
| **Minimum node requirements** | 3 | 4 | Page 797, Table 67 |
| **vCPU count** | 4 | 8 | Page 797, Table 67 |
| **Memory** | 16 GiB | 32 GiB | Page 797, Table 67 |
| **Disk volume** | Approximately 80 GiB (for /var/lib/kubelet and /var/lib/containerd) | Approximately 80 GiB (for /var/lib/kubelet and /var/lib/containerd) | Page 797, Table 67 |
| **Root volume** | Disk usage must be below 85% | Disk usage must be below 85% | Page 797, Table 67 |

**Managed Cluster Minimum Requirements:**

| Resource | Control Plane Node | Worker Node | Reference |
|----------|-------------------|-------------|-----------|
| **Minimum node requirements** | 3 | 4 | Page 797, Table 68 |
| **vCPU count** | 4 | 8 | Page 797, Table 68 |
| **Memory** | 12 GiB | 12 GiB | Page 797, Table 68 |
| **Disk volume** | Approximately 80 GiB (for /var/lib/kubelet and /var/lib/containerd) | Approximately 80 GiB (for /var/lib/kubelet and /var/lib/containerd) | Page 797, Table 68 |
| **Root volume** | Disk usage must be below 85% | Disk usage must be below 85% | Page 797, Table 68 |

**Default Configuration:**
- If you follow the instructions to create a cluster using the default NKP settings without modifying the configuration files or additional flags, you can deploy the cluster with three control plane nodes and four worker nodes, matching the requirements in the General Resource Requirements for Pro and Ultimate Clusters table. (Page 797)

**Official Documentation Reference:**
- Page 797: Table 67 - General Resource Requirements for Pro and Ultimate Clusters
- Page 797: Table 68 - Resource Requirements for Managed Clusters

### Pre-provisioned Installation Requirements

**Control Plane Machines:**
- 15% of free space is available on the root file system
- Multiple ports are open as described in NKP ports
- firewalld systemd service is disabled (Page 55)

**Worker Machines:**
- 15% of free space is available on the root file system
- Multiple ports are open as described in the NKP ports
- If you plan to use local volume provisioning to provide persistent volumes for your workloads, you must mount at least four volumes to the `/mnt/disks/` mount point on each machine. Each volume must have at least 100 GiB of capacity. (Page 55)

**Official Documentation Reference:**
- Page 55: Pre-provisioned Installation Options

### Machine Specifications (Pre-provisioned)

**Control Plane Machines:**
- **Minimum:** At least three Control Plane Machines required
- **vCPU:** 4 cores
- **Memory:** 16 GB
- **Disk:** Approximately 80 GB of free space for the volume used for `/var/lib/kubelet` and `/var/lib/containerd`
- **Root volume:** 15% free space on the root file system
- **Ports:** Multiple ports open, as described in NKP Ports
- **firewalld:** Must be disabled (Page 843)

**Worker Machines:**
- **Minimum:** At least four worker machines required
- **vCPU:** 8 cores
- **Memory:** 32 GiB
- **Disk:** Around 80 GiB of free space for the volume used for `/var/lib/kubelet` and `/var/lib/containerd`
- **Root volume:** 15% free space on the root file system
- **Local volume provisioning:** If you plan to use local volume provisioning to provide persistent volumes for your workloads, you must mount at least four volumes to the `/mnt/disks/` mount point on each machine. Each volume must have at least 55 GiB of capacity. (Page 843)

**Important Notes:**
- Swap is disabled. The kubelet does not have generally available support for swap. (Page 843)
- The specific number of worker machines required for your environment can vary depending on the cluster workload and size of the machines. (Page 843)

**Official Documentation Reference:**
- Page 843: Machine Specifications

---

## Storage Requirements

### Managed Cluster Storage Requirements

To create additional clusters in your Nutanix environment, ensure that you have at least the following minimum recommended resources:

**Cluster Storage Requirements:**
- Requires a default storage class and three volumes of 10GiB, 100GiB, and 10GiB or the ability to create those volumes based on the storage class. (Page 799)

**Worker Node Storage:**
- You need four worker nodes to support the upgrades to rook-ceph platform application. rook-ceph supports the logging stack, velero backup tool, and NKP Insights. If you disable rook-ceph platform application, you need only three worker nodes. (Page 799)

**Official Documentation Reference:**
- Page 799: Nutanix Kubernetes Platform Managed Cluster Requirements

### Harbor Storage Requirements

**Storage Recommendations:**
- It is recommended you have 100 GB storage space for most use cases. (Page 435)
- To use Harbor as an Open Container Initiative (OCI) registry for charts and other artifacts, ensure that you have sufficient storage based on the size of the artifacts and charts. (Page 435)
- To use Harbor as a pull-through cache for temporarily storing images, ensure that you have sufficient storage based on the number of images you need to cache. (Page 435)

**Integrated Rook Ceph Storage:**
- Integrated Rook Ceph provides 120 GB of space by default which is shared with other services such as logging and backups. (Page 435)
- When you expand the integrated Rook Ceph storage, note that integrated Rook Ceph uses erasure coding. Therefore, you can use only 75% of the space. For example, if you add 100 GB, you can use only 75 GB to store data. (Page 435)

**Official Documentation Reference:**
- Page 435: Storage Requirements for Harbor

### Prometheus Storage Capacity

You can set a specific storage capacity for Prometheus. (Page 755)

**Official Documentation Reference:**
- Page 755: Setting Storage Capacity for Prometheus

---

## Platform Application Resource Requirements

### Workspace Platform Applications

The following table describes workspace platform applications available to clusters within a workspace, including minimum resource requirements, deployment information, and their default PriorityClasses.

**Official Documentation Reference:**
- Page 801: Workspace Platform Application Defaults and Resource Requirements
- Page 801: Table 69 - Available Workspace Platform Applications

| Common Name | Application ID | Deployed by Default | Minimum Resources | Minimum Persistent Storage | Default PriorityClass |
|------------|----------------|---------------------|-------------------|---------------------------|----------------------|
| Cert Manager | cert-manager | Yes | cpu: 10m, memory: 32Mi | Not applicable | system-cluster-critical (2000000000) |
| External DNS | external-dns | No | Not applicable | Not applicable | NKP High (100001000) |
| Fluent Bit | fluent-bit | No | cpu: 350m, memory: 350Mi | Not applicable | NKP Critical (100002000) |
| Gatekeeper | gatekeeper | Yes | cpu: 300m, memory: 768Mi | Not applicable | system-cluster-critical (2000000000) |
| Grafana | grafana-logging | No | cpu: 200m, memory: 100Mi | Not applicable | NKP Critical (100002000) |
| Loki | grafana-loki | No | Not applicable | # of PVs: 8, PV sizes: 10Gi x 8 (total: 80Gi) | NKP Critical (100002000) |
| Istio | istio | No | cpu: 1270m, memory: 4500Mi | Not applicable | NKP Critical (100002000) |
| Jaeger | jaeger | No | Not applicable | Not applicable | NKP High (100001000) |
| Kiali | kiali | No | cpu: 20m, memory: 128Mi | Not applicable | NKP High (100001000) |
| Knative | knative | No | cpu: 610m, memory: 400Mi | Not applicable | NKP High (100001000) |
| Traefik ForwardAuth | traefik-forward-auth | Yes | cpu: 100m, memory: 128Mi | Not applicable | NKP Critical (100002000) |
| Velero | velero | No | cpu: 1000m, memory: 1024Mi | Not applicable | NKP Critical (100002000) |

**Important Notes:**
- Currently, NKP only supports a single deployment of cert-manager for each cluster. Therefore, you cannot install cert-manager on Konvoy managed clusters or clusters with pre-installed cert-manager. (Page 803)
- NKP supports only a single deployment of traefik per cluster. (Page 803)
- NKP automatically manages the deployment of traefik-forward-auth and kube-oidc-proxy when you attach clusters to the workspace. The NKP user interface does not display these workspace platform applications. (Page 803)

**Official Documentation Reference:**
- Page 801-803: Workspace Platform Application Defaults and Resource Requirements

### Management Cluster Applications

The following table lists the workspace platform applications that are specific to a management cluster including their minimum resource requirements, minimum persistent storage requirements, and default PriorityClass values.

**Official Documentation Reference:**
- Page 799-800: Nutanix Kubernetes Platform Management Cluster Application Requirements

| Common Name | Application ID | Deployed by Default | Minimum Resources | Minimum Persistent Storage | Default PriorityClass |
|------------|----------------|---------------------|-------------------|---------------------------|----------------------|
| Centralized Grafana* | centralized-grafana | Yes | cpu: 200m, memory: 100Mi | Not applicable | NKP Critical (100002000) |
| Centralized OpenCost* | centralized-OpenCost | Yes | cpu: 1200m, memory: 4151Mi | # of PVs: 1, PV sizes: 32Gi | NKP High (100001000) |
| Chartmuseum | chartmuseum | Yes | Not applicable | # of PVs: 1, PV sizes: 2Gi | NKP Critical (100002000) |
| Dex | dex | Yes | cpu: 100m, memory: 50Mi | Not applicable | NKP Critical (100002000) |
| Dex Authenticator | dex-k8s-authenticator | Yes | cpu: 100m, memory: 128Mi | Not applicable | NKP High (100001000) |
| NKP Insights Management | NKP-insights-management | No | cpu: 100m, memory: 128Mi | Not applicable | NKP Critical (100002000) |
| Karma* | karma | Yes | Not applicable | Not applicable | NKP Critical (100002000) |
| Kommander | kommander | No | cpu: 1100m, memory: 896Mi | Not applicable | NKP Critical (100002000) |
| Kommander AppManagement | kommander-appmanagement | Yes | cpu: 300m, memory: 256Mi | Not applicable | NKP Critical (100002000) |
| Kommander Flux | kommander-flux | Yes | cpu: 5000m, memory: 5Gi | Not applicable | NKP Critical (100002000) |
| Kommander UI | kommander-ui | No | cpu: 100m, memory: 256Mi | Not applicable | NKP Critical (100002000) |
| Kubefed | kubefed | Yes | cpu: 300m, memory: 192Mi | Not applicable | NKP Critical (100002000) |
| Kubetunnel | kubetunnel | Yes | cpu: 200m, memory: 148Mi | Not applicable | NKP Critical (100002000) |
| Thanos* | thanos | Yes | Not applicable | Not applicable | NKP Critical (100002000) |
| Traefik ForwardAuth | traefik-forward-auth-mgmt | Yes | cpu: 100m, memory: 128Mi | Not applicable | NKP Critical (100002000) |

**Note:** Applications with an asterisk ("*") are only for NKP Ultimate users. If you have an Ultimate license, NKP deploys these applications automatically. (Page 800)

**Official Documentation Reference:**
- Page 799-800: Nutanix Kubernetes Platform Management Cluster Application Requirements

### Project Platform Applications

**Official Documentation Reference:**
- Page 517: Project Platform Application Descriptions and Resource Requirements
- Page 517: Table 44 - Project Platform Application Configuration Requirements

| Name | Minimum Resources | Suggested Minimum Persistent Storage | Required | Deployed by Default | Default PriorityClass |
|------|------------------|--------------------------------------|----------|---------------------|----------------------|
| project-grafana-logging | cpu: 200m, memory: 100Mi | No | No | No | NKP Critical (100002000) |
| project-grafana-loki | Not applicable | # of PVs: 3, PV sizes: 10Gi x 3 (total: 30Gi) | No | No | NKP Critical (100002000) |
| project-logging | Not applicable | Not applicable | No | No | NKP Critical (100002000) |

**Important Note:**
- Platform applications require more resources than solely deploying or attaching clusters into a project. Your cluster must have sufficient resources when deploying or attaching to ensure that the applications are installed successfully. (Page 517)

---

## Known Limitations

### General Limitations

**NKP Version Compatibility:**
- The NKP version you use to create a managed cluster must match the NKP version you use to delete it. (Page 256)

**EKS-Specific Limitations:**
- You cannot self-manage EKS clusters. (Page 256)

**Official Documentation Reference:**
- Page 256: Known Limitations

### Control Plane Limitations

**Control Plane Endpoint Port:**
- The control plane endpoint port is also used as the API server port on each control plane machine. The default port is 6443. Before you create the cluster, ensure the port is available for use on each control plane machine. (Page 108)

**Official Documentation Reference:**
- Page 108: Known Limitations

---

## Configuration Maximums

NKP maintains a list of supported configuration maximums that can be viewed from the Nutanix Support Portal.

**Accessing Configuration Maximums:**
- You can view the latest list of supported configuration maximums from the Nutanix Support Portal. For more information, see NKP Configuration Maximums. Ensure that you select the required NKP version from the list. (Page 798)

**Note:** A Nutanix account is required to access the Nutanix Support Portal. (Page 798)

**Official Documentation Reference:**
- Page 798: Nutanix Kubernetes Platform Configuration Maximums

---

## Infrastructure Provider Requirements

### Infrastructure Provider-Specific Requirements

Additional requirements might apply to certain infrastructure providers. For example, the Nutanix Kubernetes Platform (NKP) on Azure by default deploys a Standard_D4s_v3 VM with a 128 GiB volume for the operating system and an 80 GiB volume for etcd storage, which meets the specified requirements. (Page 798)

**Official Documentation Reference:**
- Page 798: Infrastructure Provider-Specific Requirements
- For more information on resource requirements, see the relevant installation options for the respective infrastructure provider:
  - Nutanix Installation Options on page 54
  - Pre-provisioned Installation Options on page 55
  - AWS Installation Options on page 155
  - Azure Installation Options on page 342
  - vSphere Installation Options on page 264
  - EKS Installation Options on page 243
  - AKS Installation Options on page 353

### Nutanix Enterprise AI Requirements

**Minimum Resource Requirements:**
- Ensure to resize your Kubernetes worker nodes from 8 vCPU to 12 vCPU before upgrading Nutanix Enterprise AI. This is required to meet minimum resource requirements and ensure a successful upgrade. (Page 480)

**Required Applications:**
Before upgrading Nutanix Enterprise AI, enable the following applications on your managed cluster:
- Cert Manager
- Prometheus Monitoring
- NVIDIA GPU Operator
- Envoy Gateway
- Kserve
- OpenTelemetry Operator (Page 480)

**Official Documentation Reference:**
- Page 480: Nutanix Enterprise AI Requirements

---

## Summary Table

| Category | Resource | Limit/Requirement | Reference |
|----------|----------|-------------------|-----------|
| **Production Deployment** | | | |
| Control Plane Nodes | Minimum | 3 nodes | Page 795, 843 |
| Worker Nodes | Minimum | 4 nodes | Page 795, 843 |
| **Starter Edition - Management** | | | |
| Control Plane vCPU | Minimum | 2 cores | Page 796, Table 65 |
| Control Plane Memory | Minimum | 8 GiB | Page 796, Table 65 |
| Worker vCPU | Minimum | 4 cores | Page 796, Table 65 |
| Worker Memory | Minimum | 8 GiB | Page 796, Table 65 |
| **Starter Edition - Managed** | | | |
| Control Plane vCPU | Minimum | 2 cores | Page 796, Table 66 |
| Control Plane Memory | Minimum | 6 GiB | Page 796, Table 66 |
| Worker vCPU | Minimum | 3 cores | Page 796, Table 66 |
| Worker Memory | Minimum | 6 GiB | Page 796, Table 66 |
| **Pro/Ultimate Edition - Management** | | | |
| Control Plane vCPU | Minimum | 4 cores | Page 797, Table 67 |
| Control Plane Memory | Minimum | 16 GiB | Page 797, Table 67 |
| Worker vCPU | Minimum | 8 cores | Page 797, Table 67 |
| Worker Memory | Minimum | 32 GiB | Page 797, Table 67 |
| **Pro/Ultimate Edition - Managed** | | | |
| Control Plane vCPU | Minimum | 4 cores | Page 797, Table 68 |
| Control Plane Memory | Minimum | 12 GiB | Page 797, Table 68 |
| Worker vCPU | Minimum | 8 cores | Page 797, Table 68 |
| Worker Memory | Minimum | 12 GiB | Page 797, Table 68 |
| **Storage** | | | |
| Disk volume (per node) | Minimum | Approximately 80 GiB | Page 796-797, 843 |
| Root volume usage | Maximum | 85% (15% free required) | Page 796-797, 843 |
| Harbor storage | Recommended | 100 GB | Page 435 |
| Managed cluster volumes | Required | 10GiB, 100GiB, 10GiB | Page 799 |
| **Platform Applications** | | | |
| cert-manager deployments | Maximum | 1 per cluster | Page 803 |
| traefik deployments | Maximum | 1 per cluster | Page 803 |

---

## References

### Official NKP 2.17 Documentation

1. **Resource Requirements:**
   - Page 795: Control Plane Nodes and Worker Nodes Resource Requirements for Nutanix Kubernetes Platform
   - Page 796: Table 65 - Resource Requirements for Management Cluster (Starter)
   - Page 796: Table 66 - Resource Requirements for Managed Cluster (Starter)
   - Page 797: Table 67 - General Resource Requirements for Pro and Ultimate Clusters
   - Page 797: Table 68 - Resource Requirements for Managed Clusters (Pro/Ultimate)
   - Page 843: Machine Specifications

2. **Platform Applications:**
   - Page 801: Workspace Platform Application Defaults and Resource Requirements
   - Page 801: Table 69 - Available Workspace Platform Applications
   - Page 799-800: Nutanix Kubernetes Platform Management Cluster Application Requirements
   - Page 517: Project Platform Application Descriptions and Resource Requirements

3. **Storage Requirements:**
   - Page 435: Storage Requirements for Harbor
   - Page 755: Setting Storage Capacity for Prometheus
   - Page 799: Nutanix Kubernetes Platform Managed Cluster Requirements

4. **Known Limitations:**
   - Page 108: Known Limitations (Control Plane)
   - Page 256: Known Limitations (General)

5. **Configuration Maximums:**
   - Page 798: Nutanix Kubernetes Platform Configuration Maximums

6. **Infrastructure Provider Requirements:**
   - Page 798: Infrastructure Provider-Specific Requirements
   - Page 480: Nutanix Enterprise AI Requirements

### Additional Resources

- [Nutanix Kubernetes Platform Documentation Portal](https://portal.nutanix.com/page/documents/details?targetId=Nutanix-Kubernetes-Platform-v2_17:Nutanix-Kubernetes-Platform-v2_17)
- [Nutanix Support Portal - NKP Configuration Maximums](https://portal.nutanix.com) (Requires Nutanix account)
- [Kubernetes Scalability Thresholds](https://kubernetes.io/docs/setup/best-practices/cluster-large/)

---

## Version Information

This document is based on Nutanix Kubernetes Platform (NKP) 2.17 User Guide. All limits and requirements mentioned are applicable to NKP 2.17. For the most up-to-date information, always refer to the official NKP 2.17 User Guide PDF.

**Source Document:** `~/Downloads/Nutanix-Kubernetes-Platform-v2_17.pdf`

**Last Updated:** January 2026

---

## Notes

1. **Edition-Specific Requirements:** Different NKP editions (Starter, Pro, Ultimate) have different minimum resource requirements. Ensure you meet the requirements for your specific edition.

2. **Production vs. Development:** While single control plane node deployments are possible, they are not recommended for production. Production deployments require a minimum of 3 control plane nodes for high availability.

3. **Storage Considerations:**
   - Root volume usage must be below 85% (15% free space required)
   - Disk volumes require approximately 80 GiB for `/var/lib/kubelet` and `/var/lib/containerd`
   - Local volume provisioning requires at least four volumes of 55-100 GiB each mounted at `/mnt/disks/`

4. **Platform Application Overhead:** Platform applications require additional resources beyond the base cluster requirements. Ensure your cluster has sufficient resources when deploying or attaching clusters to accommodate platform applications.

5. **Configuration Maximums:** For the latest list of supported configuration maximums, refer to the Nutanix Support Portal (requires Nutanix account).

6. **Infrastructure Provider Variations:** Different infrastructure providers (Nutanix AHV, AWS, Azure, GCP, vSphere) may have provider-specific requirements. Refer to the relevant installation options pages for provider-specific details.
