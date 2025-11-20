# Envoy 404 Analysis: Why ClusterIP Returns 404

## Problem

When accessing the Cilium Gateway ClusterIP with Host header:
```bash
curl http://172.26.4.210/ -H "Host: mailer3.kuprin.su"
```

**Response**: `HTTP/1.1 404 Not Found` from Envoy

## Key Observations

1. ✅ **Request reaches Envoy** (response shows `server: envoy`)
2. ✅ **Host header is preserved** (`Host: mailer3.kuprin.su` is sent)
3. ❌ **Returns 404** (virtual host or route doesn't match, or backend unavailable)

## Envoy Configuration

From the config dump:

### Virtual Host
- **Name**: `mailer/cilium-gateway-mail-in-a-pods-gateway-test/mailer3.kuprin.su`
- **Domains**: `["mailer3.kuprin.su", "mailer3.kuprin.su:*"]`
- **Routes**: 
  - Path: `/` (prefix match)
  - Cluster: `mailer/cilium-gateway-mail-in-a-pods-gateway-test/mailer:mail-in-a-pods-statics-server:80`

### Listener
- **Address**: `127.0.0.1:10285`
- **Name**: `mailer/cilium-gateway-mail-in-a-pods-gateway-test/listener`

## Why 404?

A 404 from Envoy can mean:

### 1. Virtual Host Doesn't Match

**Unlikely** because:
- Host header: `mailer3.kuprin.su`
- Virtual host domains: `["mailer3.kuprin.su", "mailer3.kuprin.su:*"]`
- Should match exactly

### 2. Route Doesn't Match

**Unlikely** because:
- Request path: `/`
- Route match: `prefix: "/"`
- Should match

### 3. Cluster Has No Healthy Endpoints

**Possible** - The cluster `mailer/cilium-gateway-mail-in-a-pods-gateway-test/mailer:mail-in-a-pods-statics-server:80` might:
- Have no endpoints
- Have unhealthy endpoints
- Not be resolved by EDS (Endpoint Discovery Service)

### 4. Backend Service Returns 404

**Possible** - The backend service `mail-in-a-pods-statics-server:80` might:
- Return 404 for the root path `/`
- Not be running
- Have no pods

## Debugging Steps

### 1. Check Backend Service

```bash
kubectl get svc mail-in-a-pods-statics-server -n mailer
kubectl get endpoints mail-in-a-pods-statics-server -n mailer
```

### 2. Test Direct Backend Access

```bash
STATICS_SVC_IP=$(kubectl get svc mail-in-a-pods-statics-server -n mailer -o jsonpath='{.spec.clusterIP}')
kubectl exec -n mailer <pod> -- curl http://${STATICS_SVC_IP}/
```

### 3. Check Envoy Cluster Health

```bash
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg envoy admin clusters | grep statics-server
```

### 4. Check Envoy Stats

```bash
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg envoy admin metrics | grep -i "404\|cluster\|upstream"
```

## Most Likely Cause

Based on the evidence:

**The cluster `mailer/cilium-gateway-mail-in-a-pods-gateway-test/mailer:mail-in-a-pods-statics-server:80` has no healthy endpoints.**

This could be because:
1. EDS (Endpoint Discovery Service) hasn't resolved the endpoints yet
2. The backend service has no pods
3. The backend pods are not ready
4. There's a network policy blocking traffic

## Solution

1. **Verify backend service has endpoints**:
   ```bash
   kubectl get endpoints mail-in-a-pods-statics-server -n mailer
   ```

2. **Check if backend pods are running**:
   ```bash
   kubectl get pods -n mailer -l app.kubernetes.io/name=statics-server
   ```

3. **Check Envoy cluster status**:
   ```bash
   kubectl exec -n kube-system <cilium-pod> -- cilium-dbg envoy admin clusters
   ```

4. **If endpoints exist but Envoy shows unhealthy**, restart Cilium/Envoy to refresh EDS

## Note

The fact that Envoy returns 404 (not connection reset) is actually **good news**:
- It means the request is reaching Envoy
- Host header is being preserved
- Virtual host matching is working (or would work if cluster was healthy)
- The issue is likely with the backend cluster/endpoints


