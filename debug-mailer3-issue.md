# Debug: mailer3.kuprin.su Not Working on Cilium Gateway

## Problem

- `mailer2.kuprin.su` works on `108.61.117.121` (Cilium Gateway)
- `mailer3.kuprin.su` does NOT work on `108.61.117.121` (Connection reset by peer)
- Both HTTPRoutes are accepted and programmed

## Configuration

### Gateway: mail-in-a-pods-gateway-test
- **Gateway Class**: `cilium`
- **LoadBalancer IP**: `108.61.117.121`
- **HTTP Listener**: `hostname: ""` (no restriction)
- **Status**: Programmed, 1 route attached

### HTTPRoute: mail-in-a-pods-test-routes-http
- **Hostname**: `mailer3.kuprin.su`
- **Parent**: `mail-in-a-pods-gateway-test` (http, https)
- **Backend**: `mail-in-a-pods-statics-server:80`
- **Status**: Accepted by both NGINX and Cilium controllers

## Symptoms

1. **External Request**:
   ```bash
   curl http://108.61.117.121/ -H 'Host: mailer3.kuprin.su'
   # Result: Connection reset by peer
   ```

2. **Internal Request** (from pod):
   ```bash
   curl http://108.61.117.121/ -H 'Host: mailer3.kuprin.su'
   # Result: HTTP 404
   ```

3. **Working Request**:
   ```bash
   curl http://108.61.117.121/ -H 'Host: mailer2.kuprin.su'
   # Result: Returns HTML (works!)
   ```

## Analysis

### Why mailer2.kuprin.su Works

The HTTPRoute `gateway-test-nginx-http` is attached to `gateway-test-nginx`, but somehow works on `mail-in-a-pods-gateway-test` (108.61.117.121). This suggests:
- Cilium Gateway may be ignoring HTTPRoute hostname filters
- Or there's a catch-all/default route behavior

### Why mailer3.kuprin.su Doesn't Work

Even though:
- HTTPRoute is accepted ✅
- Gateway listener has no hostname restriction ✅
- Route is programmed ✅

The connection is reset, suggesting:
1. **Envoy doesn't have a matching route** for `mailer3.kuprin.su`
2. **Hostname matching is strict** in Cilium Gateway (unlike NGINX)
3. **Envoy configuration issue** - route not properly configured

## Possible Causes

### 1. Cilium Gateway Strict Hostname Matching

Cilium Gateway may enforce HTTPRoute hostname matching strictly, even when Gateway listener has no hostname restriction. This is different from NGINX Gateway Fabric behavior.

### 2. Envoy Configuration Issue

The Envoy listener may not have the route configured correctly. Check Envoy config dump:
```bash
kubectl port-forward -n kube-system <cilium-envoy-pod> 15000:15000
curl http://localhost:15000/config_dump | jq '.configs[2].dynamic_listeners[] | select(.name | contains("mail-in-a-pods-gateway-test"))'
```

### 3. Multiple Controller Conflict

The HTTPRoute shows status from both:
- `gateway.nginx.org/nginx-gateway-controller` (NGINX)
- `io.cilium/gateway-controller` (Cilium)

Both controllers are processing the same HTTPRoute, which may cause conflicts.

### 4. Gateway Class Mismatch

The Gateway uses `cilium` GatewayClass, but the HTTPRoute status shows it's also accepted by NGINX controller. This dual-controller state may cause issues.

## Debugging Steps

1. **Check Envoy Routes**:
   ```bash
   kubectl port-forward -n kube-system <cilium-envoy-pod> 15000:15000
   curl http://localhost:15000/config_dump | jq '.configs[2].dynamic_listeners[].active_state.listener.filter_chains[] | select(.filters[].name == "envoy.filters.network.http_connection_manager")'
   ```

2. **Check Cilium Gateway Logs**:
   ```bash
   kubectl logs -n kube-system -l k8s-app=cilium --tail=100 | grep -i "mailer3\|gateway\|httproute"
   ```

3. **Check Envoy Logs**:
   ```bash
   kubectl logs -n kube-system -l k8s-app=cilium-envoy --tail=100 | grep -i "mailer3\|gateway\|listener"
   ```

4. **Verify HTTPRoute is only attached to Cilium Gateway**:
   ```bash
   kubectl get httproute mail-in-a-pods-test-routes-http -n mailer -o jsonpath='{.spec.parentRefs[*].name}'
   ```

5. **Test with Hubble**:
   ```bash
   hubble observe --ip 108.61.117.121 --follow --last 20
   # Then make request to mailer3.kuprin.su
   ```

## Solutions

### Option 1: Remove NGINX Controller Status

If the HTTPRoute should only be handled by Cilium, ensure it's not attached to NGINX Gateway:
```bash
kubectl get httproute mail-in-a-pods-test-routes-http -n mailer -o yaml
# Check parentRefs - should only have mail-in-a-pods-gateway-test
```

### Option 2: Verify Hostname Matching

Cilium Gateway may require exact hostname match. Verify the HTTPRoute hostname exactly matches the request:
```yaml
spec:
  hostnames:
  - mailer3.kuprin.su  # Must match exactly (case-sensitive)
```

### Option 3: Add Catch-All Route

If hostname matching is the issue, add a catch-all HTTPRoute:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mail-in-a-pods-catchall
  namespace: mailer
spec:
  # No hostnames = matches all hostnames
  parentRefs:
  - name: mail-in-a-pods-gateway-test
    sectionName: http
  rules:
  - backendRefs:
    - name: mail-in-a-pods-statics-server
      port: 80
```

### Option 4: Check Backend Service

Verify the backend service is accessible:
```bash
kubectl get svc mail-in-a-pods-statics-server -n mailer
kubectl get endpoints mail-in-a-pods-statics-server -n mailer
```

## Root Cause Hypothesis

Based on the testing:
- **Without Host header**: Returns 404 (Envoy responds, route exists)
- **With Host: mailer3.kuprin.su**: Connection reset (route configured but doesn't work)
- **With Host: mailer2.kuprin.su**: Returns HTML (works, but no route for it!)

This suggests **Cilium Gateway has a bug or unexpected behavior**:
1. HTTPRoute with `hostnames: ["mailer3.kuprin.su"]` is accepted but doesn't work
2. Requests with `mailer2.kuprin.su` work even though there's no HTTPRoute for it on this gateway
3. This indicates Cilium Gateway may be ignoring HTTPRoute hostname filters

## Next Steps

1. **Check if `gateway-test-nginx-http` is also attached to `mail-in-a-pods-gateway-test`**:
   ```bash
   kubectl get httproute gateway-test-nginx-http -n mailer -o jsonpath='{.spec.parentRefs[*].name}'
   ```

2. **Check Envoy configuration dump** to see actual routes:
   ```bash
   kubectl port-forward -n kube-system <cilium-envoy-pod> 15000:15000
   curl http://localhost:15000/config_dump | jq '.configs[2].dynamic_listeners[] | select(.name | contains("mail-in-a-pods-gateway-test"))'
   ```

3. **Remove hostname from HTTPRoute** to test if it's a hostname matching issue:
   ```bash
   kubectl patch httproute mail-in-a-pods-test-routes-http -n mailer --type json \
     -p='[{"op": "remove", "path": "/spec/hostnames"}]'
   ```

4. **Verify backend service is reachable**:
   ```bash
   kubectl get svc mail-in-a-pods-statics-server -n mailer
   kubectl get endpoints mail-in-a-pods-statics-server -n mailer
   ```

