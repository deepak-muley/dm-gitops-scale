# Resource Sizing Quick Reference

> **Beginner-friendly summary** of resource sizing strategies for platform services.
>
> **Last Updated:** January 2026

---

## 🎯 Golden Rule: Observe First, Then Optimize

**⚠️ NEVER set resource requests/limits without observing actual usage first!**

1. **Start** with temporary conservative estimates
2. **Observe** actual usage for 1-2 weeks
3. **Measure** p95/p99 percentiles
4. **Adjust** based on real data

---

## 📊 Understanding Percentiles (p95, p99)

### Simple Explanation

**Percentiles tell you "most of the time" vs. "rarely but possible":**

| Percentile | Meaning | Example |
|------------|---------|---------|
| **p50** | Half the time, usage was this or less | "50% of the time, CPU ≤ 300m" |
| **p95** | 95% of the time, usage was this or less | "95% of the time, CPU ≤ 500m" |
| **p99** | 99% of the time, usage was this or less | "99% of the time, CPU ≤ 800m" |

### Visual Example

```
CPU Usage Over Time:
│
│                    ╱╲  ← Rare spike (p99 = 800m)
│                  ╱  ╲
│                ╱    ╲
│              ╱      ╲
│            ╱        ╲
│          ╱          ╲ ← Typical peak (p95 = 500m)
│        ╱            ╲
│      ╱              ╲
│    ╱                ╲
│  ╱                  ╲
│╱____________________╲
│
Request = p95 × 1.2 = 600m  (covers typical usage)
Limit   = p99 × 1.5 = 1200m (allows rare spikes)
```

### How to Use

- **p95** → Use for **Requests** (guaranteed resources)
- **p99** → Use for **Limits** (maximum allowed)

---

## 🧮 Simple Sizing Formulas

### Step 1: Measure Actual Usage (1-2 weeks)

```bash
# Check current usage
kubectl top pods -A --containers

# Get p95/p99 from Prometheus (see full guide for queries)
```

### Step 2: Calculate Resources

```
CPU Request = p95 CPU Usage × 1.2  (20% headroom)
CPU Limit   = p99 CPU Usage × 1.5  (50% headroom)

Memory Request = p95 Memory Usage × 1.2  (20% headroom)
Memory Limit   = p99 Memory Usage × 1.3  (30% headroom)
```

### Step 3: Apply

```yaml
resources:
  requests:
    cpu: 600m      # p95 (500m) × 1.2
    memory: 614Mi  # p95 (512Mi) × 1.2
  limits:
    cpu: 1200m     # p99 (800m) × 1.5
    memory: 1024Mi # p99 (768Mi) × 1.3
```

---

## 📋 Tier-Based Quick Reference

### XS Tier (1-10 Clusters)

**Total Platform Resources:**
- CPU: ~1.5 cores (requests), ~3 cores (limits)
- Memory: ~4 Gi (requests), ~8 Gi (limits)

**Key Services:**
- Prometheus: 500m CPU, 2Gi memory
- Grafana: 200m CPU, 256Mi memory
- Loki: 500m CPU, 1Gi memory

### S Tier (10-50 Clusters)

**Total Platform Resources:**
- CPU: ~4-6 cores (requests), ~8-12 cores (limits)
- Memory: ~8-12 Gi (requests), ~16-24 Gi (limits)

**Key Services:**
- Prometheus: 1000m CPU, 4Gi memory
- Grafana: 500m CPU, 512Mi memory
- Loki: 1000m CPU, 2Gi memory

### M Tier (50-200 Clusters)

**Total Platform Resources:**
- CPU: ~12-18 cores (requests), ~24-36 cores (limits)
- Memory: ~24-36 Gi (requests), ~48-72 Gi (limits)

**Key Services:**
- Prometheus (sharded): 2000m CPU, 8Gi memory
- Grafana: 1000m CPU, 1Gi memory
- Loki (distributed): 2000m CPU, 4Gi memory
- Thanos Query: 1000m CPU, 2Gi memory

### L Tier (200-1,000 Clusters)

**Total Platform Resources:**
- CPU: ~30-50 cores (requests), ~60-100 cores (limits)
- Memory: ~60-100 Gi (requests), ~120-200 Gi (limits)

**Key Services:**
- Prometheus (sharded): 4000m CPU, 16Gi memory
- Grafana: 2000m CPU, 2Gi memory
- Loki (distributed): 4000m CPU, 8Gi memory
- Thanos (full stack): Multiple components

---

## 🚀 Actionable Workflow

### Week 1-2: Observe

```bash
# 1. Apply temporary conservative estimates
kubectl patch deployment my-app -n my-namespace --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/resources", 
   "value": {
     "requests": {"cpu": "200m", "memory": "256Mi"},
     "limits": {"cpu": "500m", "memory": "512Mi"}
   }}
]'

# 2. Monitor actual usage
kubectl top pods -A --containers

# 3. Collect p95/p99 metrics (use Prometheus queries from full guide)
```

### Week 3-4: Optimize

```bash
# 1. Calculate optimal values from p95/p99
# CPU Request = p95 × 1.2
# CPU Limit = p99 × 1.5

# 2. Apply optimized values
kubectl patch deployment my-app -n my-namespace --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", 
   "value": "600m"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", 
   "value": "1200m"}
]'

# 3. Monitor for issues (throttling, OOM kills)
kubectl get events --sort-by='.lastTimestamp' | grep -E "Throttling|OOMKilled"
```

### Ongoing: Continuous Improvement

- Review monthly
- Adjust quarterly
- Use VPA (Vertical Pod Autoscaler) for automation

---

## 🛠️ Quick Commands

### Check Current Usage

```bash
# Current resource usage
kubectl top pods -A --containers

# Current resource configuration
kubectl get pods -A -o json | \
  jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): CPU=\(.spec.containers[].resources.requests.cpu // "none"), Memory=\(.spec.containers[].resources.requests.memory // "none")"'
```

### Find Pods Missing Resources

```bash
# Pods without resource requests/limits
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.spec.containers[].resources == null) | "\(.metadata.namespace)/\(.metadata.name)"'
```

### Check for Issues

```bash
# CPU throttling
kubectl get events --sort-by='.lastTimestamp' | grep Throttling

# OOM kills
kubectl get events --sort-by='.lastTimestamp' | grep OOMKilled

# Pending pods (resource constraints)
kubectl get pods -A --field-selector=status.phase=Pending
```

---

## 📚 Common Patterns

### Stateless Application (API Server)

```yaml
resources:
  requests:
    cpu: 200m      # Typical: 150m × 1.3
    memory: 256Mi  # Typical: 200Mi × 1.3
  limits:
    cpu: 500m      # Request × 2.5
    memory: 512Mi  # Request × 2
```

### Stateful Application (Database)

```yaml
resources:
  requests:
    cpu: 1000m     # Higher CPU for queries
    memory: 4Gi    # Higher memory for caching
  limits:
    cpu: 2000m     # Request × 2
    memory: 8Gi    # Request × 2
```

### Observability (Prometheus)

```yaml
resources:
  requests:
    cpu: 2000m     # M tier sizing
    memory: 8Gi
  limits:
    cpu: 4000m
    memory: 16Gi
```

---

## ⚠️ Common Mistakes

| Mistake | Problem | Solution |
|---------|---------|----------|
| Setting limits too low | OOM kills, throttling | Use p99 × 1.5 for limits |
| Setting requests too high | Wasted resources, scheduling issues | Use p95 × 1.2 for requests |
| Not observing first | Wrong sizing, wasted time | Always measure 1-2 weeks first |
| Using average instead of p95 | Under-provisioning | Use p95/p99, not average |
| Setting same for all apps | Over/under-provisioning | Size each app individually |

---

## 📖 Related Documents

- **[RESOURCE-SIZING-STRATEGIES.md](./RESOURCE-SIZING-STRATEGIES.md)** - Complete detailed guide
- **[SCALING-ACTIONABLE-GUIDE.md](./SCALING-ACTIONABLE-GUIDE.md)** - Scaling management clusters
- **[NKP-Sizing-Scale-Guide.md](../nkp/NKP-Sizing-Scale-Guide.md)** - NKP-specific sizing

---

## 🎓 Key Takeaways

1. **Always observe first** - Never set resources without measuring actual usage
2. **Use p95 for requests** - Covers typical peak usage
3. **Use p99 for limits** - Allows rare spikes
4. **Add headroom** - 20% for requests, 30-50% for limits
5. **Review regularly** - Usage patterns change over time
6. **Start conservative** - Better to over-provision initially, then optimize

---

*Quick Reference - For detailed explanations, see [RESOURCE-SIZING-STRATEGIES.md](./RESOURCE-SIZING-STRATEGIES.md)*
