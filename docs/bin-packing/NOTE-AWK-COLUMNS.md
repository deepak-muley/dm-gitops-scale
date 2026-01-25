# Note: awk Column Numbers for kubectl get pods

When using `kubectl get pods -o wide`, the column numbers for the NODE field depend on whether you use `-A` (all namespaces) or not.

## Column Layout

### Without `-A` (Single Namespace)
```
NAME                              READY   STATUS    RESTARTS   AGE   IP           NODE
$1                                $2      $3        $4          $5    $6           $7
```
**NODE is column 7**

### With `-A` (All Namespaces)
```
NAMESPACE   NAME                              READY   STATUS    RESTARTS   AGE   IP           NODE
$1          $2                                $3      $4        $5          $6    $7           $8
```
**NODE is column 8**

## Examples

### Single Namespace (NODE = $7)
```bash
# Default namespace
kubectl get pods -o wide | awk '{print $7}'

# Specific namespace
kubectl get pods -n monitoring -o wide | awk '{print $7}'
```

### All Namespaces (NODE = $8)
```bash
# All namespaces
kubectl get pods -A -o wide | awk '{print $8}'

# With --all-namespaces flag
kubectl get pods --all-namespaces -o wide | awk '{print $8}'
```

## Safe Approach

To avoid confusion, you can use a more robust approach:

```bash
# Using column name (requires column command)
kubectl get pods -A -o wide | column -t | awk '{print $NF}'  # Last column

# Or use JSONPath (most reliable)
kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
```

## Quick Reference

| Command | NODE Column |
|---------|-------------|
| `kubectl get pods -o wide` | $7 |
| `kubectl get pods -n <ns> -o wide` | $7 |
| `kubectl get pods -A -o wide` | $8 |
| `kubectl get pods --all-namespaces -o wide` | $8 |
