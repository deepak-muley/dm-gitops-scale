# Resource Sizing Strategies: Requests, Limits, and Quotas for Platform Services

> **Purpose:** Comprehensive guide for determining resource requests, limits, and quotas for applications with many pods and containers, with tier-based sizing strategies (XS, S, M, L) for platform services.
>
> **Last Updated:** January 2026
>
> **📖 Quick Reference:** For a beginner-friendly summary, see [RESOURCE-SIZING-QUICK-REFERENCE.md](./RESOURCE-SIZING-QUICK-REFERENCE.md)

---

## Table of Contents

1. [Overview](#overview)
2. [Key Concepts](#key-concepts)
3. [Measurement Strategies](#measurement-strategies)
4. [Determining Resource Requests and Limits](#determining-resource-requests-and-limits)
5. [Tier-Based Sizing Strategies](#tier-based-sizing-strategies)
6. [Platform Service Sizing by Tier](#platform-service-sizing-by-tier)
7. [Resource Quota Strategies](#resource-quota-strategies)
8. [Implementation Workflow](#implementation-workflow)
9. [Tools and Techniques](#tools-and-techniques)
10. [Common Patterns and Examples](#common-patterns-and-examples)
11. [Troubleshooting](#troubleshooting)

---

## Overview

Determining the right resource requests, limits, and quotas for applications with many pods and containers requires a systematic approach that combines:

1. **Observation**: ⚠️ **CRITICAL - Always observe actual usage first!**
2. **Measurement**: Understanding actual resource consumption (p95/p99)
3. **Analysis**: Identifying patterns and outliers
4. **Sizing**: Setting appropriate requests and limits based on data
5. **Validation**: Testing and monitoring
6. **Iteration**: Continuous refinement

> **🎯 Key Principle: Never set resource requests/limits without observing actual usage first!**
> 
> - Start with temporary conservative estimates
> - Observe for 1-2 weeks to collect real usage data
> - Then adjust based on p95/p99 percentiles
> 
> See [Implementation Workflow](#implementation-workflow) for the complete process.

This guide provides strategies for each step, with specific recommendations for different cluster sizes (XS, S, M, L).

---

## Key Concepts

### Understanding Percentiles (p95, p99) - Beginner's Guide

**What are Percentiles?**

Percentiles help you understand typical vs. extreme resource usage. Think of them as "most of the time" vs. "rarely but possible."

#### Real-World Analogy

Imagine you're tracking how many people visit a store each day over 100 days:

- **p50 (median)**: Half the days had this many or fewer visitors
  - Example: 50 visitors → "Half the time, we had 50 or fewer visitors"
  
- **p95**: 95% of the days had this many or fewer visitors
  - Example: 80 visitors → "95% of the time, we had 80 or fewer visitors"
  - Only 5% of days had more than 80 visitors
  
- **p99**: 99% of the days had this many or fewer visitors
  - Example: 100 visitors → "99% of the time, we had 100 or fewer visitors"
  - Only 1% of days had more than 100 visitors

#### For Resource Sizing

When measuring CPU or memory usage:

- **p95 CPU Usage**: 95% of the time, your application used this much CPU or less
  - Example: 500m (0.5 cores) → "95% of the time, it used ≤0.5 cores"
  - The other 5% of the time, it used more (spikes)
  
- **p99 CPU Usage**: 99% of the time, your application used this much CPU or less
  - Example: 800m (0.8 cores) → "99% of the time, it used ≤0.8 cores"
  - Only 1% of the time, it used more (rare spikes)

#### Why Use p95 and p99?

| Metric | Use For | Why |
|--------|---------|-----|
| **p95** | Setting **Requests** | Represents typical peak usage (covers 95% of cases) |
| **p99** | Setting **Limits** | Represents extreme but acceptable usage (covers 99% of cases) |

**Example Calculation:**

If your application's CPU usage shows:
- p95 = 500m (0.5 cores)
- p99 = 800m (0.8 cores)

Then set:
- **CPU Request** = 500m × 1.2 = 600m (covers typical usage with 20% headroom)
- **CPU Limit** = 800m × 1.5 = 1200m (allows rare spikes with 50% headroom)

**Visual Example:**

```
CPU Usage Over Time:
│
│                    ╱╲  ← Rare spike (p99)
│                  ╱  ╲
│                ╱    ╲
│              ╱      ╲
│            ╱        ╲
│          ╱          ╲ ← Typical peak (p95)
│        ╱            ╲
│      ╱              ╲
│    ╱                ╲
│  ╱                  ╲
│╱____________________╲
│
Request = p95 × 1.2  (covers typical usage)
Limit   = p99 × 1.5  (allows rare spikes)
```

**Key Takeaway**: p95 tells you "normal peak usage," p99 tells you "extreme but acceptable usage." Use p95 for requests (guaranteed), p99 for limits (maximum allowed).

### Resource Requests vs Limits

| Concept | Purpose | Impact | When Exceeded |
|---------|---------|--------|---------------|
| **Request** | Minimum guaranteed resources | Used for scheduling decisions | Pod may not be scheduled if unavailable |
| **Limit** | Maximum allowed resources | Hard cap on consumption | CPU throttled, Memory OOMKilled |

### Resource Quotas vs Limit Ranges

| Concept | Scope | Purpose |
|---------|-------|---------|
| **Resource Quota** | Namespace-level | Limits total resources across all pods in a namespace |
| **Limit Range** | Namespace-level | Sets default/min/max per pod/container |

### Tier Definitions

| Tier | Clusters | Machines | Management Cluster Size | Platform Services Complexity |
|------|----------|----------|------------------------|------------------------------|
| **XS** | 1-10 | < 100 | Small (3-5 nodes) | Basic observability, minimal platform services |
| **S** | 10-50 | 100-500 | Medium (5-8 nodes) | Standard observability, moderate platform services |
| **M** | 50-200 | 500-2,000 | Large (8-15 nodes) | Advanced observability, comprehensive platform services |
| **L** | 200-1,000 | 2,000-10,000 | XL (15-30 nodes) | Enterprise observability, full platform stack |

---

## Measurement Strategies

### Strategy 1: Baseline Measurement (Week 1-2)

**Goal**: Understand current resource consumption patterns.

#### Step 1: Collect Resource Usage Data

```bash
#!/bin/bash
# measure-resources.sh - Run for 1-2 weeks

NAMESPACE="platform-services"  # Change to your namespace
DURATION="14d"  # 2 weeks

echo "=== Collecting Resource Usage Data ==="
echo "Namespace: $NAMESPACE"
echo "Duration: $DURATION"
echo ""

# 1. Current resource requests/limits
echo "=== Current Resource Configuration ==="
kubectl get pods -n $NAMESPACE -o json | \
  jq -r '.items[] | 
    "\(.metadata.name)\t\(.spec.containers[].resources.requests.cpu // "none")\t\(.spec.containers[].resources.requests.memory // "none")\t\(.spec.containers[].resources.limits.cpu // "none")\t\(.spec.containers[].resources.limits.memory // "none")"'

# 2. Actual resource usage (requires metrics-server)
echo ""
echo "=== Actual Resource Usage (Current) ==="
kubectl top pods -n $NAMESPACE --containers

# 3. Export historical data (if using Prometheus)
echo ""
echo "=== Prometheus Queries (Run in Grafana) ==="
cat <<EOF
# CPU Usage (p95 over 14 days)
histogram_quantile(0.95,
  sum(rate(container_cpu_usage_seconds_total{namespace="$NAMESPACE"}[5m])) by (pod, container)
)

# Memory Usage (p95 over 14 days)
histogram_quantile(0.95,
  sum(rate(container_memory_working_set_bytes{namespace="$NAMESPACE"}[5m])) by (pod, container)
)

# CPU Throttling
sum(rate(container_cpu_cfs_throttled_seconds_total{namespace="$NAMESPACE"}[5m])) by (pod, container)

# OOM Kills
sum(increase(container_oom_kills_total{namespace="$NAMESPACE"}[1h])) by (pod, container)
EOF
```

#### Step 2: Analyze Patterns

```bash
#!/bin/bash
# analyze-resources.sh

NAMESPACE="platform-services"

echo "=== Resource Analysis ==="

# 1. Pods without resource requests
echo "=== Pods Missing Resource Requests ==="
kubectl get pods -n $NAMESPACE -o json | \
  jq -r '.items[] | select(.spec.containers[].resources.requests == null) | .metadata.name'

# 2. Pods without resource limits
echo ""
echo "=== Pods Missing Resource Limits ==="
kubectl get pods -n $NAMESPACE -o json | \
  jq -r '.items[] | select(.spec.containers[].resources.limits == null) | .metadata.name'

# 3. Resource utilization ratio (requests vs usage)
echo ""
echo "=== Resource Utilization Analysis ==="
kubectl top pods -n $NAMESPACE --containers | \
  awk 'NR>1 {print $1, $2, $3}' | \
  while read pod cpu mem; do
    requests=$(kubectl get pod $pod -n $NAMESPACE -o json | \
      jq -r '.spec.containers[].resources.requests.cpu // "0"')
    echo "$pod: CPU Request=$requests, Usage=$cpu"
  done
```

### Strategy 2: Historical Analysis (Week 2-4)

**Goal**: Identify peak usage, trends, and outliers.

#### Prometheus Queries for Historical Analysis

```promql
# CPU Usage Percentiles (14 days)
quantile_over_time(0.50, 
  rate(container_cpu_usage_seconds_total{namespace="platform-services"}[5m])[14d:]
)  # p50
quantile_over_time(0.95, 
  rate(container_cpu_usage_seconds_total{namespace="platform-services"}[5m])[14d:]
)  # p95
quantile_over_time(0.99, 
  rate(container_cpu_usage_seconds_total{namespace="platform-services"}[5m])[14d:]
)  # p99

# Memory Usage Percentiles (14 days)
quantile_over_time(0.50,
  container_memory_working_set_bytes{namespace="platform-services"}[14d:]
)  # p50
quantile_over_time(0.95,
  container_memory_working_set_bytes{namespace="platform-services"}[14d:]
)  # p95
quantile_over_time(0.99,
  container_memory_working_set_bytes{namespace="platform-services"}[14d:]
)  # p99

# Peak Usage (14 days)
max_over_time(
  rate(container_cpu_usage_seconds_total{namespace="platform-services"}[5m])[14d:]
)
max_over_time(
  container_memory_working_set_bytes{namespace="platform-services"}[14d:]
)

# CPU Throttling Rate
sum(rate(container_cpu_cfs_throttled_seconds_total{namespace="platform-services"}[5m])) 
  by (pod, container)

# OOM Kill Rate
sum(increase(container_oom_kills_total{namespace="platform-services"}[1h])) 
  by (pod, container)
```

### Strategy 3: Load Testing

**Goal**: Understand behavior under load.

```bash
#!/bin/bash
# load-test-resources.sh

NAMESPACE="platform-services"
DEPLOYMENT="my-app"

echo "=== Load Testing Resource Requirements ==="

# 1. Scale up gradually
for replicas in 1 2 5 10 20; do
  echo "Testing with $replicas replicas..."
  kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=$replicas
  
  # Wait for stabilization
  kubectl wait --for=condition=available deployment/$DEPLOYMENT -n $NAMESPACE --timeout=5m
  
  # Measure resource usage
  echo "Resource usage at $replicas replicas:"
  kubectl top pods -n $NAMESPACE -l app=$DEPLOYMENT
  
  # Wait before next scale
  sleep 5m
done

# 2. Generate load (if applicable)
echo "Generating load..."
# Use your load testing tool (e.g., k6, Apache Bench, etc.)

# 3. Monitor during load
watch -n 5 "kubectl top pods -n $NAMESPACE -l app=$DEPLOYMENT"
```

---

## Determining Resource Requests and Limits

### Formula-Based Approach

#### CPU Requests

```
CPU Request = p95 CPU Usage × 1.2 (20% headroom)
```

**Rationale**: 
- p95 captures typical peak usage
- 20% headroom accounts for variability
- Prevents CPU throttling under normal load

#### CPU Limits

```
CPU Limit = p99 CPU Usage × 1.5 (50% headroom)
OR
CPU Limit = CPU Request × 2-3 (2-3x multiplier)
```

**Rationale**:
- p99 captures extreme but acceptable peaks
- 1.5x multiplier allows burst capacity
- Alternative: Simple 2-3x multiplier for simplicity

#### Memory Requests

```
Memory Request = p95 Memory Usage × 1.2 (20% headroom)
```

**Rationale**:
- Memory is less bursty than CPU
- 20% headroom is usually sufficient
- Prevents scheduling failures

#### Memory Limits

```
Memory Limit = p99 Memory Usage × 1.3 (30% headroom)
OR
Memory Limit = Memory Request × 1.5-2 (1.5-2x multiplier)
```

**Rationale**:
- Memory limits should be conservative (OOM kills are disruptive)
- 1.3x multiplier prevents excessive memory usage
- Alternative: 1.5-2x for simplicity

### Example Calculation

**Given Metrics:**
- p95 CPU: 500m (0.5 cores)
- p99 CPU: 800m (0.8 cores)
- p95 Memory: 512Mi
- p99 Memory: 768Mi

**Calculated Resources:**
```yaml
resources:
  requests:
    cpu: 600m      # 500m × 1.2
    memory: 614Mi  # 512Mi × 1.2
  limits:
    cpu: 1200m     # 800m × 1.5 (or 600m × 2)
    memory: 1024Mi # 768Mi × 1.3 (or 614Mi × 1.67)
```

### Rule-Based Approach

For applications where measurement is difficult or not yet available:

| Application Type | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------------|-------------|-----------|----------------|--------------|
| **Lightweight** (nginx, static web) | 100m | 200m | 128Mi | 256Mi |
| **Standard** (API servers, microservices) | 200m | 500m | 256Mi | 512Mi |
| **Medium** (databases, caches) | 500m | 1000m | 512Mi | 1Gi |
| **Heavy** (Prometheus, large databases) | 1000m | 2000m | 2Gi | 4Gi |
| **Very Heavy** (ML workloads, analytics) | 2000m+ | 4000m+ | 4Gi+ | 8Gi+ |

---

## Tier-Based Sizing Strategies

### XS Tier (1-10 Clusters)

**Characteristics:**
- Minimal platform services
- Basic observability
- Low resource requirements

**Strategy:**
- Start with conservative estimates
- Use rule-based sizing initially
- Measure and adjust after 1-2 weeks

**Platform Service Sizing:**

| Service | CPU Request | CPU Limit | Memory Request | Memory Limit | Replicas |
|---------|-------------|-----------|----------------|--------------|----------|
| Prometheus | 500m | 1000m | 2Gi | 4Gi | 1 |
| Grafana | 200m | 500m | 256Mi | 512Mi | 1 |
| Alertmanager | 100m | 200m | 128Mi | 256Mi | 1 |
| Loki | 500m | 1000m | 1Gi | 2Gi | 1 |
| Logging Operator | 200m | 500m | 256Mi | 512Mi | 1 |

**Total Platform Resources:**
- CPU: ~1.5 cores (requests), ~3 cores (limits)
- Memory: ~4 Gi (requests), ~8 Gi (limits)

### S Tier (10-50 Clusters)

**Characteristics:**
- Standard platform services
- Moderate observability
- Medium resource requirements

**Strategy:**
- Use measurement-based sizing
- Implement resource quotas
- Enable HPA for variable workloads

**Platform Service Sizing:**

| Service | CPU Request | CPU Limit | Memory Request | Memory Limit | Replicas |
|---------|-------------|-----------|----------------|--------------|----------|
| Prometheus | 1000m | 2000m | 4Gi | 8Gi | 1-2 |
| Grafana | 500m | 1000m | 512Mi | 1Gi | 2 |
| Alertmanager | 200m | 500m | 256Mi | 512Mi | 2 |
| Loki | 1000m | 2000m | 2Gi | 4Gi | 1-2 |
| Logging Operator | 500m | 1000m | 512Mi | 1Gi | 2 |

**Total Platform Resources:**
- CPU: ~4-6 cores (requests), ~8-12 cores (limits)
- Memory: ~8-12 Gi (requests), ~16-24 Gi (limits)

### M Tier (50-200 Clusters)

**Characteristics:**
- Advanced platform services
- Comprehensive observability
- High resource requirements

**Strategy:**
- Use historical analysis (p95/p99)
- Implement sharding/federation
- Use dedicated node pools

**Platform Service Sizing:**

| Service | CPU Request | CPU Limit | Memory Request | Memory Limit | Replicas |
|---------|-------------|-----------|----------------|--------------|----------|
| Prometheus (sharded) | 2000m | 4000m | 8Gi | 16Gi | 2-3 |
| Grafana | 1000m | 2000m | 1Gi | 2Gi | 2-3 |
| Alertmanager | 500m | 1000m | 512Mi | 1Gi | 3 |
| Loki (distributed) | 2000m | 4000m | 4Gi | 8Gi | 2-3 |
| Logging Operator | 1000m | 2000m | 1Gi | 2Gi | 3 |
| Thanos Query | 1000m | 2000m | 2Gi | 4Gi | 2 |
| Thanos Store | 2000m | 4000m | 4Gi | 8Gi | 2 |

**Total Platform Resources:**
- CPU: ~12-18 cores (requests), ~24-36 cores (limits)
- Memory: ~24-36 Gi (requests), ~48-72 Gi (limits)

### L Tier (200-1,000 Clusters)

**Characteristics:**
- Enterprise platform services
- Full observability stack
- Very high resource requirements

**Strategy:**
- Use complete Thanos stack
- Implement multi-region deployment
- Use object storage for long-term data

**Platform Service Sizing:**

| Service | CPU Request | CPU Limit | Memory Request | Memory Limit | Replicas |
|---------|-------------|-----------|----------------|--------------|----------|
| Prometheus (sharded) | 4000m | 8000m | 16Gi | 32Gi | 3-4 |
| Grafana | 2000m | 4000m | 2Gi | 4Gi | 3-5 |
| Alertmanager | 1000m | 2000m | 1Gi | 2Gi | 3-5 |
| Loki (distributed) | 4000m | 8000m | 8Gi | 16Gi | 3-4 |
| Logging Operator | 2000m | 4000m | 2Gi | 4Gi | 3-5 |
| Thanos Query | 2000m | 4000m | 4Gi | 8Gi | 3-5 |
| Thanos Store | 4000m | 8000m | 8Gi | 16Gi | 2-3 |
| Thanos Compactor | 2000m | 4000m | 4Gi | 8Gi | 1-2 |
| Thanos Ruler | 1000m | 2000m | 2Gi | 4Gi | 2-3 |

**Total Platform Resources:**
- CPU: ~30-50 cores (requests), ~60-100 cores (limits)
- Memory: ~60-100 Gi (requests), ~120-200 Gi (limits)

---

## Platform Service Sizing by Tier

### Detailed Platform Service Configurations

#### Prometheus Sizing

| Tier | Retention | Shards | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|------|-----------|--------|-------------|-----------|----------------|--------------|---------|
| XS | 7d | 1 | 500m | 1000m | 2Gi | 4Gi | 50Gi |
| S | 15d | 1-2 | 1000m | 2000m | 4Gi | 8Gi | 100Gi |
| M | 30d | 2-3 | 2000m | 4000m | 8Gi | 16Gi | 200Gi |
| L | 30d + Thanos | 3-4 | 4000m | 8000m | 16Gi | 32Gi | 200Gi + Object Storage |

**Configuration Example (M Tier):**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: prometheus
        args:
        - '--storage.tsdb.retention.time=30d'
        - '--storage.tsdb.retention.size=200GB'
        - '--storage.tsdb.wal-compression'
        - '--query.max-concurrency=20'
        resources:
          requests:
            cpu: "2000m"
            memory: "8Gi"
          limits:
            cpu: "4000m"
            memory: "16Gi"
```

#### Grafana Sizing

| Tier | Users | Dashboards | CPU Request | CPU Limit | Memory Request | Memory Limit | Replicas |
|------|-------|------------|-------------|-----------|----------------|--------------|----------|
| XS | < 10 | < 50 | 200m | 500m | 256Mi | 512Mi | 1 |
| S | 10-50 | 50-200 | 500m | 1000m | 512Mi | 1Gi | 2 |
| M | 50-200 | 200-500 | 1000m | 2000m | 1Gi | 2Gi | 2-3 |
| L | 200+ | 500+ | 2000m | 4000m | 2Gi | 4Gi | 3-5 |

#### Loki Sizing

| Tier | Log Volume | CPU Request | CPU Limit | Memory Request | Memory Limit | Replicas | Storage |
|------|------------|-------------|-----------|----------------|--------------|----------|---------|
| XS | < 10 GB/day | 500m | 1000m | 1Gi | 2Gi | 1 | 100Gi |
| S | 10-50 GB/day | 1000m | 2000m | 2Gi | 4Gi | 1-2 | 200Gi |
| M | 50-200 GB/day | 2000m | 4000m | 4Gi | 8Gi | 2-3 | 500Gi |
| L | 200+ GB/day | 4000m | 8000m | 8Gi | 16Gi | 3-4 | 1Ti + Object Storage |

---

## Resource Quota Strategies

### Tier-Based Resource Quotas

#### XS Tier Quota

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: platform-services-quota
  namespace: platform-services
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    pods: "50"
    persistentvolumeclaims: "10"
    services: "20"
```

#### S Tier Quota

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: platform-services-quota
  namespace: platform-services
spec:
  hard:
    requests.cpu: "50"
    requests.memory: 100Gi
    limits.cpu: "100"
    limits.memory: 200Gi
    pods: "200"
    persistentvolumeclaims: "20"
    services: "50"
```

#### M Tier Quota

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: platform-services-quota
  namespace: platform-services
spec:
  hard:
    requests.cpu: "200"
    requests.memory: 400Gi
    limits.cpu: "400"
    limits.memory: 800Gi
    pods: "500"
    persistentvolumeclaims: "50"
    services: "100"
```

#### L Tier Quota

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: platform-services-quota
  namespace: platform-services
spec:
  hard:
    requests.cpu: "500"
    requests.memory: 1Ti
    limits.cpu: "1000"
    limits.memory: 2Ti
    pods: "1000"
    persistentvolumeclaims: "100"
    services: "200"
```

### Limit Ranges

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: platform-services-limits
  namespace: platform-services
spec:
  limits:
  - default:
      cpu: "1000m"
      memory: "1Gi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "4000m"
      memory: "4Gi"
    min:
      cpu: "50m"
      memory: "64Mi"
    type: Container
```

---

## Implementation Workflow

### Phase 1: Assessment (Week 1-2)

1. **Inventory Current State**
   ```bash
   # List all pods without resource requests/limits
   kubectl get pods -A -o json | \
     jq -r '.items[] | select(.spec.containers[].resources == null) | .metadata.namespace + "/" + .metadata.name'
   ```

2. **Collect Baseline Metrics**
   - Run measurement scripts for 1-2 weeks
   - Export Prometheus metrics
   - Document current resource usage

3. **Identify Gaps**
   - Pods missing requests/limits
   - Namespaces without quotas
   - Services with incorrect sizing

### Phase 2: Optimize Based on Observations (Week 3-4)

**🎯 Goal: Adjust resources based on actual usage data collected in Phase 1**

1. **Analyze Collected Data**
   - Calculate p95/p99 from Prometheus metrics
   - Identify outliers and patterns
   - Document findings

2. **Apply Formula-Based Sizing**
   - Use p95 for requests: `Request = p95 × 1.2`
   - Use p99 for limits: `Limit = p99 × 1.5`
   - Adjust based on observed patterns

3. **Create Resource Quotas**
   - Set namespace-level quotas based on tier
   - Create limit ranges
   - Document quota allocations

4. **Deploy and Monitor**
   - Apply optimized resource configurations
   - Monitor for scheduling issues
   - Check for OOM kills or throttling
   - Compare new usage vs. old usage

### Phase 3: Optimization (Week 5-8)

1. **Measure Actual Usage**
   - Collect p95/p99 metrics
   - Identify outliers
   - Document patterns

2. **Adjust Resources**
   - Update requests based on p95
   - Update limits based on p99
   - Optimize over-provisioned services

3. **Implement Automation**
   - Deploy VPA (Vertical Pod Autoscaler)
   - Set up HPA (Horizontal Pod Autoscaler)
   - Create monitoring dashboards

### Phase 4: Continuous Improvement (Ongoing)

1. **Regular Reviews**
   - Monthly resource usage review
   - Quarterly quota adjustments
   - Annual capacity planning

2. **Optimization**
   - Right-size over-provisioned services
   - Scale up under-provisioned services
   - Implement cost optimization

---

## Tools and Techniques

### Tool 1: Vertical Pod Autoscaler (VPA)

**Purpose**: Automatically recommend or adjust resource requests/limits based on usage.

**Deployment:**
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: prometheus-vpa
  namespace: monitoring
spec:
  targetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: prometheus
  updatePolicy:
    updateMode: "Off"  # Start with recommendations only
  resourcePolicy:
    containerPolicies:
    - containerName: prometheus
      minAllowed:
        cpu: 500m
        memory: 2Gi
      maxAllowed:
        cpu: 8000m
        memory: 32Gi
```

**Usage:**
```bash
# Check VPA recommendations
kubectl describe vpa prometheus-vpa -n monitoring

# Switch to Auto mode after validation
kubectl patch vpa prometheus-vpa -n monitoring --type=merge -p '{"spec":{"updatePolicy":{"updateMode":"Auto"}}}'
```

### Tool 2: Resource Usage Dashboard

**Grafana Dashboard Queries:**

```promql
# Resource Requests vs Usage
sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace, pod)
sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace, pod)

# Resource Limits vs Usage
sum(kube_pod_container_resource_limits{resource="cpu"}) by (namespace, pod)
sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace, pod)

# CPU Throttling
sum(rate(container_cpu_cfs_throttled_seconds_total[5m])) by (namespace, pod)

# Memory OOM Kills
sum(increase(container_oom_kills_total[1h])) by (namespace, pod)

# Resource Utilization Ratio
sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace, pod) /
sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace, pod)
```

### Tool 3: Resource Analysis Script

```bash
#!/bin/bash
# analyze-resource-sizing.sh

NAMESPACE="${1:-platform-services}"

echo "=== Resource Sizing Analysis for $NAMESPACE ==="
echo ""

# 1. Pods without resources
echo "=== Pods Missing Resource Configuration ==="
kubectl get pods -n $NAMESPACE -o json | \
  jq -r '.items[] | 
    select(.spec.containers[].resources == null) | 
    "\(.metadata.name) - Missing resources"'

# 2. Resource utilization
echo ""
echo "=== Resource Utilization (Requests vs Usage) ==="
kubectl top pods -n $NAMESPACE --containers | \
  awk 'NR>1 {print $1, $2, $3}' | \
  while read pod cpu mem; do
    requests=$(kubectl get pod $pod -n $NAMESPACE -o json 2>/dev/null | \
      jq -r '.spec.containers[].resources.requests.cpu // "none"' 2>/dev/null)
    if [ "$requests" != "none" ] && [ "$requests" != "null" ]; then
      echo "$pod: Request=$requests, Usage=$cpu"
    fi
  done

# 3. Quota usage
echo ""
echo "=== Resource Quota Usage ==="
kubectl describe resourcequota -n $NAMESPACE

# 4. Recommendations
echo ""
echo "=== Recommendations ==="
echo "1. Review pods without resource configuration"
echo "2. Compare requests vs actual usage"
echo "3. Adjust resources based on p95/p99 metrics"
echo "4. Consider VPA for automatic optimization"
```

---

## Common Patterns and Examples

### Pattern 1: Stateless Application

**Characteristics:**
- Predictable resource usage
- Horizontal scaling
- No persistent storage

**Example:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: api
        image: my-api:latest
        resources:
          requests:
            cpu: 200m      # Based on p95: 150m × 1.3
            memory: 256Mi  # Based on p95: 200Mi × 1.3
          limits:
            cpu: 500m      # Request × 2.5
            memory: 512Mi  # Request × 2
```

### Pattern 2: Stateful Application (Database)

**Characteristics:**
- Higher memory requirements
- CPU spikes during queries
- Persistent storage

**Example:**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: postgres
        image: postgres:14
        resources:
          requests:
            cpu: 1000m      # Based on p95: 800m × 1.25
            memory: 4Gi     # Based on p95: 3Gi × 1.3
          limits:
            cpu: 2000m      # Request × 2
            memory: 8Gi     # Request × 2
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 100Gi
```

### Pattern 3: Observability Stack (Prometheus)

**Characteristics:**
- Memory-intensive
- CPU spikes during queries
- Growing storage requirements

**Example:**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.48.0
        args:
        - '--storage.tsdb.retention.time=30d'
        - '--storage.tsdb.retention.size=200GB'
        - '--storage.tsdb.wal-compression'
        resources:
          requests:
            cpu: 2000m      # M tier sizing
            memory: 8Gi
          limits:
            cpu: 4000m
            memory: 16Gi
  volumeClaimTemplates:
  - metadata:
      name: prometheus-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 200Gi
```

---

## Troubleshooting

### Issue: Pods Not Scheduled

**Symptoms:**
- Pods stuck in Pending state
- "Insufficient resources" errors

**Solutions:**
```bash
# Check node capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check resource quotas
kubectl describe resourcequota -n <namespace>

# Reduce resource requests
kubectl patch deployment <deployment> -n <namespace> --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "100m"}
]'
```

### Issue: CPU Throttling

**Symptoms:**
- High CPU throttling metrics
- Slow application performance

**Solutions:**
```bash
# Check throttling
kubectl top pods --containers | grep <pod-name>

# Increase CPU limit
kubectl patch deployment <deployment> -n <namespace> --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "2000m"}
]'
```

### Issue: OOM Kills

**Symptoms:**
- Pods restarting frequently
- "OOMKilled" in pod status

**Solutions:**
```bash
# Check memory usage
kubectl top pods --containers | grep <pod-name>

# Increase memory limit
kubectl patch deployment <deployment> -n <namespace> --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "2Gi"}
]'
```

### Issue: Over-Provisioning

**Symptoms:**
- Low resource utilization
- High infrastructure costs

**Solutions:**
```bash
# Analyze actual usage vs requests
kubectl top pods --containers
kubectl get pods -o json | jq '.items[].spec.containers[].resources.requests'

# Use VPA recommendations
kubectl describe vpa <vpa-name> -n <namespace>

# Reduce resource requests
kubectl patch deployment <deployment> -n <namespace> --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "100m"}
]'
```

---

## Quick Reference: Tier-Based Sizing Summary

| Tier | Total CPU (Requests) | Total Memory (Requests) | Total CPU (Limits) | Total Memory (Limits) | Key Services |
|------|---------------------|------------------------|-------------------|----------------------|--------------|
| **XS** | ~1.5 cores | ~4 Gi | ~3 cores | ~8 Gi | Basic observability |
| **S** | ~4-6 cores | ~8-12 Gi | ~8-12 cores | ~16-24 Gi | Standard observability |
| **M** | ~12-18 cores | ~24-36 Gi | ~24-36 cores | ~48-72 Gi | Advanced observability + Thanos |
| **L** | ~30-50 cores | ~60-100 Gi | ~60-100 cores | ~120-200 Gi | Full stack + Multi-region |

---

## References

- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [SCALING-ACTIONABLE-GUIDE.md](./SCALING-ACTIONABLE-GUIDE.md) - Comprehensive scaling guide
- [NKP-Sizing-Scale-Guide.md](../nkp/NKP-Sizing-Scale-Guide.md) - NKP-specific sizing

---

*Document generated: January 2026*
*For platform-specific sizing, refer to tier-based recommendations in this document.*
