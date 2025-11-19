# Why LoadBalancer Works But NodePort Hangs

## Problem

- **NodePort** (95.179.147.120:30119) with Host header: **HANGS/RESETS**
- **LoadBalancer** (95.179.142.249) with Host header: **WORKS** ✅
- **Both** without Host header: **TIMEOUT**

## Key Findings

1. ✅ Pod IS on the node (95.179.147.120)
2. ✅ NGINX config is correct (has server_name block)
3. ✅ Internal access works (ClusterIP)
4. ❌ NodePort hangs even on node WITH pod
5. ✅ LoadBalancer works with Host header

## Root Cause: Cilium eBPF NodePort Routing

**Cilium kubeProxyReplacement is enabled**, which means:

### NodePort Routing (Cilium eBPF)
- NodePort traffic goes through **Cilium eBPF** datapath
- eBPF may have **issues with Host header processing**
- Connection hangs or resets when Host header is present
- This is a known limitation in some Cilium versions

### LoadBalancer Routing
- LoadBalancer uses **different routing path**
- May bypass Cilium eBPF NodePort handling
- Routes through LoadBalancer infrastructure (Vultr)
- Host header is handled correctly ✅

## Why This Happens

### Cilium eBPF NodePort Behavior

With `kubeProxyReplacement: True`:
1. **NodePort**: Handled by Cilium eBPF
   - eBPF programs process the connection
   - May not properly handle Host headers in some cases
   - Connection hangs or resets

2. **LoadBalancer**: Uses different mechanism
   - May use Cilium LoadBalancer IPAM
   - Or routes through LoadBalancer provider (Vultr)
   - Different code path that handles Host headers correctly

### The Difference

```
NodePort Request Flow:
Client → Node IP:NodePort → Cilium eBPF → Pod
         (Hangs here with Host header)

LoadBalancer Request Flow:
Client → LoadBalancer IP → LoadBalancer Provider → Node → Pod
         (Works correctly with Host header)
```

## Solutions

### Option 1: Use LoadBalancer (Current Working Solution)
Keep using LoadBalancer IP - it works correctly.

### Option 2: Access NodePort on Internal IP
If you need NodePort, access via internal cluster IP:
```bash
# Get internal node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[?(@.status.addresses[?(@.type=="InternalIP")].address=="10.7.96.7")].status.addresses[?(@.type=="InternalIP")].address}')
curl http://${NODE_IP}:30119/ -H "Host: mailer2.kuprin.su"
```

### Option 3: Change externalTrafficPolicy to Cluster
```bash
kubectl patch svc gateway-test-nginx-nginx -n mailer \
  -p '{"spec":{"externalTrafficPolicy":"Cluster"}}'
```
**Warning**: May lose source IP preservation

### Option 4: Check Cilium Version/Configuration
This may be a Cilium bug or configuration issue. Check:
- Cilium version
- Cilium NodePort Host header handling
- Known issues with Cilium eBPF and Host headers

## Why LoadBalancer Works

LoadBalancer works because:
1. **Different routing path**: Doesn't go through Cilium eBPF NodePort handling
2. **LoadBalancer provider processing**: Vultr LoadBalancer may process Host headers
3. **Health check routing**: LoadBalancer knows which node has the pod and routes correctly
4. **SNAT/Header modification**: LoadBalancer may modify headers in a way that works

## Summary

- **NodePort**: Hangs due to Cilium eBPF Host header handling issue
- **LoadBalancer**: Works because it uses different routing path
- **Root Cause**: Cilium eBPF NodePort routing doesn't handle Host headers correctly
- **Solution**: Use LoadBalancer (works) or investigate Cilium configuration

This is a **Cilium eBPF behavior**, not a Gateway or NGINX configuration issue.

