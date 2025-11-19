# Why NodePort Hangs But LoadBalancer Works

## Problem

- **NodePort access** (95.179.147.120:30119) with Host header: **HANGS**
- **LoadBalancer access** (95.179.142.249) with Host header: **WORKS**

## Root Cause: externalTrafficPolicy: Local

The service uses `externalTrafficPolicy: Local`, which means:

### How externalTrafficPolicy: Local Works

1. **Traffic only routes to nodes WITH pods**
   - If you access a node that doesn't have the pod, the connection hangs
   - Kubernetes doesn't forward traffic to other nodes

2. **LoadBalancer behavior**
   - LoadBalancer may route to the node WITH the pod
   - Or LoadBalancer may have health checks that route correctly

3. **NodePort behavior**
   - NodePort is accessible on ALL nodes
   - But with `Local` policy, only nodes WITH pods can serve traffic
   - Nodes WITHOUT pods will hang/timeout

## Why NodePort Hangs (Even on Node WITH Pod!)

**Critical Finding**: The pod IS on the node, but NodePort still hangs!

When you access `95.179.147.120:30119`:
1. Request reaches node `95.179.147.120` ✅
2. NodePort is listening on that node ✅
3. Gateway pod IS on that node ✅
4. But connection hangs/resets when Host header is present ❌
5. LoadBalancer works on the same node ✅

This suggests the issue is **NOT** about pod location, but about **how NodePort handles Host headers** vs how LoadBalancer handles them.

## Why LoadBalancer Works

When you access `95.179.142.249`:
1. LoadBalancer receives the request
2. LoadBalancer may do SNAT (Source NAT) - changes source IP
3. LoadBalancer may modify or preserve Host header differently
4. LoadBalancer routes through its infrastructure (not direct node access)
5. Request is served correctly ✅

**Key Difference**: LoadBalancer processes the request through its infrastructure, while NodePort is direct node access that may have different Host header handling.

## Possible Causes

### 1. Host Header Processing at Node Level

NodePort may process Host headers differently than LoadBalancer:
- **NodePort**: Direct node access, may have stricter Host header validation
- **LoadBalancer**: Processes through LoadBalancer infrastructure, may be more lenient

### 2. Connection Handling Differences

- **NodePort**: Direct TCP connection to node, may timeout differently
- **LoadBalancer**: Managed connection through LoadBalancer, may have keepalive/timeout settings

### 3. Source IP Preservation

With `externalTrafficPolicy: Local`:
- **NodePort**: Preserves source IP, may affect Host header processing
- **LoadBalancer**: May do SNAT, changing how Host header is handled

### 4. kube-proxy vs Cilium Routing

If using Cilium with `kubeProxyReplacement`:
- NodePort routing may go through Cilium eBPF
- LoadBalancer may use different routing path
- Different Host header handling in eBPF vs traditional routing

## Solution

### Option 1: Change externalTrafficPolicy to Cluster

```bash
kubectl patch svc gateway-test-nginx-nginx -n mailer \
  -p '{"spec":{"externalTrafficPolicy":"Cluster"}}'
```

**Pros**: NodePort will work on all nodes
**Cons**: May lose source IP preservation

### Option 2: Access NodePort on Node WITH Pod

```bash
# Get node IP where pod is running
NODE_IP=$(kubectl get pod <gateway-pod> -n mailer -o jsonpath='{.status.hostIP}')
NODEPORT=$(kubectl get svc gateway-test-nginx-nginx -n mailer -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

# Access on correct node
curl http://${NODE_IP}:${NODEPORT}/ -H "Host: mailer2.kuprin.su"
```

### Option 3: Use LoadBalancer (Current Working Solution)

Keep using LoadBalancer IP - it routes correctly.

## Testing

To verify which node has the pod:

```bash
# Get pod location
kubectl get pods -n mailer -l gateway.networking.k8s.io/gateway-name=gateway-test-nginx -o wide

# Check if 95.179.147.120 has the pod
# If not, that's why NodePort hangs on that node
```

## Critical Finding: Cilium kubeProxyReplacement

**Cilium kubeProxyReplacement is enabled**, which means:
- NodePort routing goes through **Cilium eBPF** (not kube-proxy)
- LoadBalancer may use a **different routing path**
- **Host header processing differs** between NodePort (eBPF) and LoadBalancer

## Why LoadBalancer Works But NodePort Hangs

### LoadBalancer (Works with Host Header)
1. Request goes to Vultr LoadBalancer
2. LoadBalancer may do **SNAT** (Source NAT)
3. LoadBalancer routes to node through **different path** (not eBPF NodePort)
4. Host header is **preserved/modified** by LoadBalancer
5. Request reaches NGINX with correct Host header ✅

### NodePort (Hangs with Host Header)
1. Request goes directly to node IP:port
2. Goes through **Cilium eBPF** routing (kubeProxyReplacement)
3. eBPF may have **different Host header handling**
4. Connection hangs or resets ❌

## The Real Issue: Cilium eBPF NodePort Host Header Processing

With Cilium `kubeProxyReplacement`:
- **NodePort**: Uses eBPF, may not handle Host headers correctly
- **LoadBalancer**: Uses different routing, handles Host headers correctly

This is a **Cilium eBPF behavior** difference, not a Kubernetes service configuration issue.

## Summary

- **NodePort**: Hangs (even on node WITH pod) - Cilium eBPF routing issue
- **LoadBalancer**: Works - Uses different routing path that handles Host headers correctly
- **Root Cause**: Cilium eBPF NodePort routing handles Host headers differently than LoadBalancer routing

The issue is **Cilium eBPF NodePort Host header processing**, not `externalTrafficPolicy: Local` or pod location.

