# Bin Packing Examples

This directory contains example configurations for applying resource bin packing to various platform services.

## Examples

### prometheus-bin-packing-example.yaml

Helm values file for installing kube-prometheus-stack with bin packing enabled.

**Features:**
- Configures Prometheus, Alertmanager, Grafana, and kube-state-metrics to use bin packing
- Includes resource requests/limits optimized for bin packing
- Shows how to balance bin packing with high availability

**Usage:**

```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# For kind cluster (default scheduler with bin packing)
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  -f prometheus-bin-packing-example.yaml

# For NKP cluster (with platform-services scheduler profile)
# 1. First enable bin packing: ./nkp-platform-bin-packing.sh enable
# 2. Update schedulerName in values file to: "platform-services"
# 3. Install:
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  -f prometheus-bin-packing-example.yaml
```

**What to Expect:**

After installation, Prometheus stack pods should:
- Concentrate on fewer nodes (2-3 nodes instead of spreading across all)
- Show higher node utilization (60-80% vs 30-40%)
- Leave more nodes available for workloads

**Verify Bin Packing:**

```bash
# Check pod distribution
kubectl get pods -n monitoring -o wide

# Count pods per node (for single namespace, node is column 7)
kubectl get pods -n monitoring -o wide --no-headers | \
  awk '{print $7}' | sort | uniq -c | sort -rn

# For all namespaces, use column 8:
kubectl get pods -A -o wide --no-headers | \
  awk '{print $8}' | sort | uniq -c | sort -rn

# Check node utilization
kubectl top nodes

# Check scheduler used
kubectl get pods -n monitoring -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.schedulerName}{"\n"}{end}'
```

## Creating Your Own Examples

When creating bin packing configurations for other services:

1. **Set schedulerName:**
   - Kind clusters: Leave empty or omit (uses default with bin packing)
   - NKP clusters: Set to `"platform-services"`

2. **Configure Resource Requests:**
   - Set appropriate CPU/memory requests
   - Bin packing works best with accurate resource requests

3. **Consider High Availability:**
   - Use pod anti-affinity for critical services
   - Balance bin packing density with HA requirements

4. **Test Gradually:**
   - Start with non-critical services
   - Monitor for resource contention
   - Adjust resource requests based on actual usage

## Additional Resources

- [Kubernetes Resource Bin Packing Guide](../../docs/bin-packing/K8s-Resource-Bin-Packing-Guide.md)
- [What to Expect Guide](../../docs/bin-packing/WHAT-TO-EXPECT.md)
- [Troubleshooting Guide](../../docs/bin-packing/TROUBLESHOOTING.md)
