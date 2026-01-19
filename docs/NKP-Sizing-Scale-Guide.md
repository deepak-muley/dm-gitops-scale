# Nutanix Kubernetes Platform (NKP) 2.17 - Sizing, Scale & Resource Guide

> **Reference Documentation:** `/Users/deepak/Documents/NKP/Nutanix-Kubernetes-Platform-v2_17.pdf`
>
> **Last Updated:** January 2026

---

## Table of Contents

1. [Overview](#overview)
2. [Cluster Architecture](#cluster-architecture)
3. [Supported Platforms](#supported-platforms)
4. [Management Cluster Sizing](#management-cluster-sizing)
5. [Workload Cluster Sizing](#workload-cluster-sizing)
6. [Scale Limits & Boundaries](#scale-limits--boundaries)
7. [Scalability Solutions & Best Practices](#scalability-solutions--best-practices)
8. [Storage Guidelines](#storage-guidelines)
9. [Network Considerations](#network-considerations)
10. [Monitoring & Observability Overhead](#monitoring--observability-overhead)
11. [Edition-Specific Considerations](#edition-specific-considerations)
12. [Quick Reference Tables](#quick-reference-tables)

---

## Overview

Nutanix Kubernetes Platform (NKP) is an enterprise Kubernetes distribution that provides:
- Multi-cluster fleet management
- Built-in observability (metrics, logs, tracing)
- GitOps-based configuration management
- Enterprise data services integration
- Support for hybrid and multi-cloud deployments

This document provides sizing guidelines, scale limits, and best practices for deploying NKP management and workload clusters.

---

## Cluster Architecture

### Cluster Types

| Cluster Type | Purpose | Components |
|--------------|---------|------------|
| **Management Cluster** | Central control plane for NKP | Kommander, Fleet management, Observability stack, GitOps controllers, Backup/restore services |
| **Workload Cluster** | Application workloads | Customer applications, services, databases |

### High Availability Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    MANAGEMENT CLUSTER                            │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐                    │
│  │ Control   │  │ Control   │  │ Control   │  (3-5 nodes for HA)│
│  │ Plane 1   │  │ Plane 2   │  │ Plane 3   │                    │
│  │ + etcd    │  │ + etcd    │  │ + etcd    │                    │
│  └───────────┘  └───────────┘  └───────────┘                    │
│  ┌───────────────────────────────────────────┐                  │
│  │  Observability Workers (Prometheus,       │                  │
│  │  Grafana, Logging, Tracing)               │                  │
│  └───────────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │  Workload   │  │  Workload   │  │  Workload   │
    │  Cluster 1  │  │  Cluster 2  │  │  Cluster N  │
    └─────────────┘  └─────────────┘  └─────────────┘
```

---

## Supported Platforms

NKP 2.x supports deployment on multiple infrastructure platforms:

| Platform | Type | Notes |
|----------|------|-------|
| **Nutanix AHV** | On-premises | Native integration with Nutanix storage, networking |
| **VMware vSphere** | On-premises | Full vSphere integration |
| **AWS** | Public Cloud | EC2-based clusters |
| **Azure** | Public Cloud | Azure VM-based clusters |
| **GCP** | Public Cloud | GCE-based clusters |
| **Bare Metal** | On-premises | Direct hardware deployment |

---

## Management Cluster Sizing

The management cluster hosts NKP control plane components and requires careful sizing based on:
- Number of managed workload clusters
- Observability retention requirements
- Number of users/tenants
- Enabled features (GitOps, backup, etc.)

### Management Cluster - Node Specifications

#### POC / Development Environment

| Component | Nodes | vCPU | RAM | Storage | Notes |
|-----------|-------|------|-----|---------|-------|
| Control Plane + etcd | 1-3 | 4-6 | 8-16 GB | 100-150 GB SSD | Single node acceptable for POC only |
| Workers (if separate) | 2 | 4 | 8-16 GB | 100 GB | For observability components |
| **Total Minimum** | 3 | 12-18 | 24-48 GB | 300-450 GB | |

#### Small Production (1-5 Workload Clusters)

| Component | Nodes | vCPU | RAM | Storage | Notes |
|-----------|-------|------|-----|---------|-------|
| Control Plane + etcd | 3 | 4-8 | 16-32 GB | 150-200 GB SSD | HA configuration |
| Workers | 2-3 | 8 | 16-32 GB | 150 GB | Observability, ingress |
| **Total Minimum** | 5-6 | 28-48 | 80-160 GB | 750-1000 GB | |

#### Medium Production (5-20 Workload Clusters)

| Component | Nodes | vCPU | RAM | Storage | Notes |
|-----------|-------|------|-----|---------|-------|
| Control Plane + etcd | 3-5 | 8-12 | 32-48 GB | 200 GB NVMe | 5 nodes for larger scale |
| Workers | 3-5 | 12-16 | 32-64 GB | 200-300 GB | Heavy observability load |
| **Total Minimum** | 6-10 | 60-110 | 192-400 GB | 1.2-2 TB | |

#### Large / Enterprise (20+ Workload Clusters)

| Component | Nodes | vCPU | RAM | Storage | Notes |
|-----------|-------|------|-----|---------|-------|
| Control Plane + etcd | 5 | 16 | 64 GB | 300 GB NVMe | Dedicated etcd nodes recommended |
| Workers | 5-10 | 16-32 | 64-128 GB | 300-500 GB | Separate pools for observability |
| **Total Minimum** | 10-15 | 160-400 | 640-1500 GB | 3-6 TB | |

### Management Cluster Sizing by Managed Clusters

| Managed Workload Clusters | Recommended Management Cluster Size |
|---------------------------|-------------------------------------|
| 1-5 clusters | Small Production |
| 5-20 clusters | Medium Production |
| 20-50 clusters | Large / Enterprise |
| 50+ clusters | Multiple management clusters or federation |

---

## Workload Cluster Sizing

Workload clusters run customer applications. Sizing depends on:
- Application resource requirements
- Number of pods/services
- Data storage needs
- GPU/specialized hardware requirements

### Workload Cluster - Control Plane Nodes

| Environment | Nodes | vCPU | RAM | Storage |
|-------------|-------|------|-----|---------|
| Development | 1 | 2-4 | 4-8 GB | 50-80 GB |
| Small Production | 3 | 4 | 8-16 GB | 100-150 GB |
| Medium Production | 3 | 4-8 | 16-32 GB | 150-200 GB |
| Large Production | 3-5 | 8-16 | 32-64 GB | 200-300 GB |

### Workload Cluster - Worker Nodes

#### General Purpose Workloads (Web, APIs, Microservices)

| Size | Nodes | vCPU/Node | RAM/Node | Storage/Node |
|------|-------|-----------|----------|--------------|
| Small | 2-3 | 4 | 16 GB | 100 GB |
| Medium | 3-5 | 8 | 32 GB | 150 GB |
| Large | 5-10 | 16 | 64 GB | 200 GB |
| X-Large | 10-20+ | 32 | 128 GB | 300 GB |

#### Memory-Intensive Workloads (Databases, Caching, Analytics)

| Size | Nodes | vCPU/Node | RAM/Node | Storage/Node |
|------|-------|-----------|----------|--------------|
| Small | 3 | 8 | 64 GB | 200 GB SSD |
| Medium | 5 | 16 | 128 GB | 500 GB NVMe |
| Large | 10+ | 32 | 256 GB | 1 TB NVMe |

#### GPU / ML / AI Workloads

| Size | Nodes | vCPU/Node | RAM/Node | GPU/Node | Storage/Node |
|------|-------|-----------|----------|----------|--------------|
| Small | 1-2 | 16 | 64 GB | 1 GPU | 500 GB NVMe |
| Medium | 3-5 | 32 | 128 GB | 2-4 GPU | 1 TB NVMe |
| Large | 10+ | 64 | 256-512 GB | 4-8 GPU | 2 TB NVMe |

---

## Scale Limits & Boundaries

### Kubernetes Default Limits

| Resource | Default Limit | Notes |
|----------|---------------|-------|
| Nodes per cluster | 5,000 | Kubernetes upstream limit |
| Pods per node | 110 | Default kubelet configuration |
| Pods per cluster | 150,000 | Practical limit |
| Services per cluster | 10,000 | |
| Namespaces per cluster | 10,000 | |
| ConfigMaps per namespace | 10,000 | |
| Secrets per namespace | 10,000 | |

### NKP Validated/Recommended Limits

| Resource | Validated Limit | Notes |
|----------|-----------------|-------|
| Worker nodes per cluster | ~100 | Validated in production designs |
| Control plane nodes | 3 or 5 | For HA; odd number for etcd quorum |
| Workload clusters per management cluster | 20-50 | Depends on management cluster sizing |
| Pods per node | 110 | Can be tuned with kubelet config |

### etcd Performance Boundaries

| Metric | Recommendation |
|--------|----------------|
| Database size | < 8 GB (recommended), 8 GB max |
| Request latency | < 10ms p99 |
| Disk IOPS | > 1000 IOPS (SSD/NVMe required) |
| Network latency between nodes | < 10ms |

---

## Scalability Solutions & Best Practices

### 1. Cluster API & GitOps Fleet Management

NKP uses Cluster API for lifecycle management and GitOps for configuration:

```yaml
# Example: Fleet management structure
fleet/
├── management-cluster/
│   └── kommander-config.yaml
├── workload-clusters/
│   ├── cluster-dev.yaml
│   ├── cluster-staging.yaml
│   └── cluster-prod.yaml
└── policies/
    ├── network-policies.yaml
    └── resource-quotas.yaml
```

**Benefits:**
- Declarative cluster provisioning
- Consistent configuration across clusters
- Automated drift detection and remediation
- Version-controlled infrastructure

### 2. Node Pools & Specialized Hardware

Create dedicated node pools for different workload types:

| Node Pool | Use Case | Configuration |
|-----------|----------|---------------|
| `general` | Standard workloads | Balanced CPU/RAM |
| `memory-optimized` | Databases, caching | High RAM, moderate CPU |
| `compute-optimized` | Batch processing | High CPU, moderate RAM |
| `gpu` | ML/AI workloads | GPU-enabled nodes |
| `storage-optimized` | Data-intensive apps | High IOPS storage |

### 3. Anti-Affinity & Failure Domain Distribution

Ensure high availability by spreading nodes across failure domains:

```yaml
# Pod anti-affinity example
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app: critical-service
      topologyKey: kubernetes.io/hostname
```

**Guidelines:**
- Control plane nodes across different physical hosts
- etcd nodes in different racks/availability zones
- Use Redundancy Factor (RF) 2 or 3 for storage
- Spread worker nodes across failure domains

### 4. Horizontal Pod Autoscaling (HPA)

Configure HPA for dynamic workload scaling:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 100
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### 5. Cluster Autoscaler

Enable automatic node scaling based on pending pods:

| Setting | Recommendation |
|---------|----------------|
| Scale-down delay | 10 minutes |
| Scale-down utilization threshold | 50% |
| Max node provision time | 15 minutes |
| Scan interval | 10 seconds |

### 6. Resource Quotas & Limit Ranges

Implement resource governance:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "100"
    requests.memory: 200Gi
    limits.cpu: "200"
    limits.memory: 400Gi
    pods: "500"
```

### 7. Multi-Cluster Federation

For very large deployments (50+ clusters):

- Deploy multiple management clusters by region/business unit
- Use federation tools for cross-cluster coordination
- Implement global load balancing
- Centralize logging/metrics at a higher level

---

## Storage Guidelines

### Storage Classes by Use Case

| Use Case | Storage Type | IOPS | Throughput | Latency |
|----------|--------------|------|------------|---------|
| etcd | NVMe SSD | > 3000 | > 500 MB/s | < 1ms |
| Control plane | SSD | > 1000 | > 200 MB/s | < 5ms |
| General workloads | SSD | > 500 | > 100 MB/s | < 10ms |
| Database workloads | NVMe | > 5000 | > 1 GB/s | < 1ms |
| Logging/metrics | SSD/HDD | > 300 | > 100 MB/s | < 20ms |
| Object storage | HDD/SSD | Variable | Variable | < 50ms |

### Nutanix Storage Integration

| Feature | Description |
|---------|-------------|
| Nutanix CSI Driver | Dynamic provisioning of Nutanix Volumes |
| Nutanix Files | NFS-based shared storage |
| Nutanix Objects | S3-compatible object storage |
| Volume Snapshots | Point-in-time volume backups |
| Volume Cloning | Fast volume duplication |

### Storage Sizing Guidelines

| Component | Minimum Storage | Recommended | Notes |
|-----------|-----------------|-------------|-------|
| OS disk (all nodes) | 50 GB | 80-100 GB | System, kubelet, container runtime |
| etcd data | 20 GB | 50-100 GB | SSD/NVMe required |
| Container images | 50 GB | 100-200 GB | Ephemeral storage |
| Logs (per node) | 20 GB | 50-100 GB | Rotate logs to prevent disk full |
| Prometheus data | 100 GB | 500 GB-2 TB | Based on retention period |
| Logging (Loki/EFK) | 100 GB | 500 GB-2 TB | Based on log volume |

---

## Network Considerations

### Network Requirements

| Component | Bandwidth | Latency | Notes |
|-----------|-----------|---------|-------|
| Control plane ↔ etcd | 1 Gbps+ | < 2ms | Critical path |
| Control plane ↔ Workers | 1 Gbps+ | < 10ms | API server communication |
| Worker ↔ Worker | 10 Gbps+ | < 5ms | Pod-to-pod traffic |
| Management ↔ Workload clusters | 1 Gbps+ | < 50ms | Can be across WAN |

### Pod Network CIDR Sizing

| Cluster Size | Pod CIDR | Max Pods | Notes |
|--------------|----------|----------|-------|
| Small (< 10 nodes) | /20 | 4,096 | |
| Medium (10-50 nodes) | /16 | 65,536 | Default recommendation |
| Large (50-100 nodes) | /14 | 262,144 | |
| X-Large (100+ nodes) | /12 | 1,048,576 | May need multiple CIDRs |

### Service CIDR Sizing

| Services Expected | Service CIDR | Max Services |
|-------------------|--------------|--------------|
| < 1,000 | /20 | 4,096 |
| 1,000 - 10,000 | /16 | 65,536 |
| > 10,000 | /12 | 1,048,576 |

---

## Monitoring & Observability Overhead

### Resource Consumption by Component

| Component | CPU (per 1000 pods monitored) | Memory | Storage (30-day retention) |
|-----------|-------------------------------|--------|----------------------------|
| Prometheus | 2-4 cores | 8-16 GB | 100-500 GB |
| Grafana | 0.5-1 core | 1-2 GB | 10 GB |
| Alertmanager | 0.25 core | 256-512 MB | 1 GB |
| Loki (logging) | 2-4 cores | 4-8 GB | 200 GB - 1 TB |
| Jaeger (tracing) | 1-2 cores | 2-4 GB | 50-200 GB |

### Retention Planning

| Retention Period | Storage Multiplier | Use Case |
|------------------|-------------------|----------|
| 7 days | 1x | Development |
| 15 days | 2x | Staging |
| 30 days | 4x | Production (standard) |
| 90 days | 12x | Production (compliance) |
| 1 year | 50x | Long-term compliance |

---

## Edition-Specific Considerations

NKP is available in multiple editions with different features:

| Feature | Starter | Pro | Ultimate |
|---------|---------|-----|----------|
| Single cluster management | ✓ | ✓ | ✓ |
| Multi-cluster fleet management | - | ✓ | ✓ |
| Multi-cloud support | - | - | ✓ |
| Advanced observability | Basic | ✓ | ✓ |
| Enterprise SSO/RBAC | - | ✓ | ✓ |
| GPU support | - | ✓ | ✓ |
| AI Navigator | - | - | ✓ |

### Resource Overhead by Edition

| Edition | Additional Management Cluster Overhead |
|---------|---------------------------------------|
| Starter | Baseline |
| Pro | +20-30% (fleet management, advanced monitoring) |
| Ultimate | +40-50% (multi-cloud controllers, AI services) |

---

## Quick Reference Tables

### Minimum Requirements Summary

| Environment | Management Cluster | Workload Cluster (per) |
|-------------|-------------------|------------------------|
| **POC/Dev** | 3 nodes: 4 vCPU, 16 GB RAM, 100 GB each | 3 nodes: 4 vCPU, 16 GB RAM, 100 GB each |
| **Small Prod** | 5 nodes: 8 vCPU, 32 GB RAM, 150 GB each | 6 nodes: 8 vCPU, 32 GB RAM, 150 GB each |
| **Medium Prod** | 8 nodes: 12 vCPU, 48 GB RAM, 200 GB each | 10 nodes: 16 vCPU, 64 GB RAM, 200 GB each |
| **Large Prod** | 12+ nodes: 16 vCPU, 64 GB RAM, 300 GB each | 20+ nodes: 32 vCPU, 128 GB RAM, 300 GB each |

### Platform-Specific Instance Types

#### AWS

| Role | Small | Medium | Large |
|------|-------|--------|-------|
| Control Plane | m5.xlarge | m5.2xlarge | m5.4xlarge |
| General Worker | m5.2xlarge | m5.4xlarge | m5.8xlarge |
| Memory Worker | r5.2xlarge | r5.4xlarge | r5.8xlarge |
| GPU Worker | p3.2xlarge | p3.8xlarge | p3.16xlarge |

#### GCP

| Role | Small | Medium | Large |
|------|-------|--------|-------|
| Control Plane | n2-standard-4 | n2-standard-8 | n2-standard-16 |
| General Worker | n2-standard-8 | n2-standard-16 | n2-standard-32 |
| Memory Worker | n2-highmem-8 | n2-highmem-16 | n2-highmem-32 |
| GPU Worker | a2-highgpu-1g | a2-highgpu-4g | a2-highgpu-8g |

#### Azure

| Role | Small | Medium | Large |
|------|-------|--------|-------|
| Control Plane | Standard_D4s_v3 | Standard_D8s_v3 | Standard_D16s_v3 |
| General Worker | Standard_D8s_v3 | Standard_D16s_v3 | Standard_D32s_v3 |
| Memory Worker | Standard_E8s_v3 | Standard_E16s_v3 | Standard_E32s_v3 |
| GPU Worker | Standard_NC6s_v3 | Standard_NC12s_v3 | Standard_NC24s_v3 |

#### Nutanix AHV

| Role | Small | Medium | Large |
|------|-------|--------|-------|
| Control Plane | 4 vCPU, 16 GB, 150 GB | 8 vCPU, 32 GB, 200 GB | 16 vCPU, 64 GB, 300 GB |
| General Worker | 8 vCPU, 32 GB, 150 GB | 16 vCPU, 64 GB, 200 GB | 32 vCPU, 128 GB, 300 GB |
| Memory Worker | 8 vCPU, 64 GB, 200 GB | 16 vCPU, 128 GB, 500 GB | 32 vCPU, 256 GB, 1 TB |
| GPU Worker | 16 vCPU, 64 GB, 500 GB + GPU | 32 vCPU, 128 GB, 1 TB + GPU | 64 vCPU, 256 GB, 2 TB + GPU |

---

## Appendix: Capacity Planning Worksheet

Use this worksheet to plan your NKP deployment:

```
=== MANAGEMENT CLUSTER ===
Number of workload clusters to manage: _____
Observability retention (days): _____
Number of concurrent users: _____
NKP Edition (Starter/Pro/Ultimate): _____

Calculated sizing:
- Control plane nodes: _____
- Worker nodes: _____
- Total vCPU: _____
- Total RAM: _____
- Total Storage: _____

=== WORKLOAD CLUSTER (per cluster) ===
Expected pod count: _____
Workload type (general/memory/GPU): _____
HA requirements (dev/prod): _____

Calculated sizing:
- Control plane nodes: _____
- Worker nodes: _____
- Total vCPU: _____
- Total RAM: _____
- Total Storage: _____

=== TOTAL INFRASTRUCTURE ===
Management cluster resources: _____
Workload clusters (count × per-cluster): _____
Total infrastructure requirement: _____
```

---

## References

- NKP 2.17 Documentation: `/Users/deepak/Documents/NKP/Nutanix-Kubernetes-Platform-v2_17.pdf`
- [Nutanix Kubernetes Platform Datasheet](https://www.nutanix.com/library/datasheets/nkp)
- [Kubernetes Scalability Thresholds](https://kubernetes.io/docs/setup/best-practices/cluster-large/)
- [Nutanix Bible - Cloud Native Services](https://www.nutanixbible.com)

---

*Document generated: January 2026*
*For the latest specifications, always refer to the official NKP documentation.*
