# Multiple LoadBalancers Serving Same Hostname

## Question

Why do two different LoadBalancer IPs both serve `mailer2.kuprin.su`?
- `95.179.142.249` (gateway-test-nginx)
- `108.61.117.121` (mail-in-a-pods-gateway-test)

Can they share the same HTTPRoute?

## Answer: Yes, HTTPRoutes Can Have Multiple Parent Refs

An HTTPRoute can be attached to **multiple Gateways** by specifying multiple `parentRefs` in the HTTPRoute spec.

**However**, in your case, they are **NOT sharing the same HTTPRoute**. Instead, both gateways have HTTP listeners without hostname restrictions, allowing them to serve the same hostname via different routes.

## Current Configuration

### LoadBalancer 1: 95.179.142.249
- **Gateway**: `gateway-test-nginx`
- **Gateway Class**: `nginx` (NGINX Gateway Fabric)
- **Service**: `gateway-test-nginx-nginx`
- **HTTPRoute**: `gateway-test-nginx-http`
  - Hostname: `mailer2.kuprin.su`
  - Parent: `gateway-test-nginx` (http, https)

### LoadBalancer 2: 108.61.117.121
- **Gateway**: `mail-in-a-pods-gateway-test`
- **Gateway Class**: `cilium` (Cilium Gateway)
- **Service**: `cilium-gateway-mail-in-a-pods-gateway-test`
- **HTTPRoute**: `mail-in-a-pods-test-routes-http`
  - Hostname: `mailer3.kuprin.su` (configured)
  - **But serves `mailer2.kuprin.su` due to Gateway listener having no hostname restriction**

## Key Finding

**They are NOT sharing the same HTTPRoute**, but both serve `mailer2.kuprin.su`:

### LoadBalancer 1: 95.179.142.249
- **HTTPRoute**: `gateway-test-nginx-http`
- **Hostname**: `mailer2.kuprin.su` ✅
- **Gateway**: `gateway-test-nginx` (NGINX Gateway Fabric)
- **Status**: Works correctly

### LoadBalancer 2: 108.61.117.121
- **HTTPRoute**: `mail-in-a-pods-test-routes-http`
- **Hostname**: `mailer3.kuprin.su` (configured)
- **Gateway**: `mail-in-a-pods-gateway-test` (Cilium Gateway)
- **Status**: **Serves `mailer2.kuprin.su` even though route is for `mailer3.kuprin.su`!**

## Mystery Solved: Gateway Listener Has No Hostname Restriction

### Key Discovery

Both gateways have **HTTP listeners without hostname restrictions**:

```yaml
# gateway-test-nginx
listeners:
- name: http
  port: 80
  hostname: ""  # Empty = accepts all hostnames

# mail-in-a-pods-gateway-test  
listeners:
- name: http
  port: 80
  hostname: ""  # Empty = accepts all hostnames
```

### Why Both Serve mailer2.kuprin.su

1. **Gateway HTTP listener** has no `hostname` → accepts **all** hostnames
2. **HTTPRoute hostname** (`mailer3.kuprin.su`) is a **request filter**, not a listener restriction
3. **Cilium Gateway behavior**: When Gateway listener has no hostname, it may:
   - Accept all HTTPRoutes attached to that listener
   - Match requests based on HTTPRoute hostname (if specified)
   - **OR** ignore HTTPRoute hostname and route all traffic (implementation-specific)

### Testing Results

- `curl http://108.61.117.121 -H 'Host: mailer2.kuprin.su'` → ✅ Returns HTML
- `curl http://108.61.117.121 -H 'Host: mailer3.kuprin.su'` → ❌ Connection error (unexpected!)

The connection error for `mailer3.kuprin.su` suggests **Cilium Gateway may have a bug** or **different hostname matching logic** than expected.

## Possible Explanations

### 1. HTTPRoute Attached to Both Gateways

If `gateway-test-nginx-http` has `mail-in-a-pods-gateway-test` in its parentRefs, it would serve on both LoadBalancers.

### 2. Multiple HTTPRoutes with Same Hostname

Both gateways might have different HTTPRoutes but with the same hostname `mailer2.kuprin.su`.

### 3. Default/Catch-All Route

One gateway might have a catch-all route that matches `mailer2.kuprin.su`.

## How to Share HTTPRoute Between Gateways

To make an HTTPRoute serve on multiple Gateways, add multiple `parentRefs`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shared-httproute
  namespace: mailer
spec:
  hostnames:
  - mailer2.kuprin.su
  parentRefs:
  - name: gateway-test-nginx
    sectionName: http
  - name: mail-in-a-pods-gateway-test  # Add second gateway
    sectionName: http
  rules:
  - backendRefs:
    - name: mail-in-a-pods-statics-server
      port: 80
```

## Benefits of Sharing HTTPRoute

1. **Single Source of Truth**: One HTTPRoute defines routing for multiple gateways
2. **Consistency**: Same routing rules across all gateways
3. **Easier Management**: Update one HTTPRoute to affect all gateways

## Considerations

1. **Gateway Controllers**: Both gateways must use compatible controllers (both use `nginx` class)
2. **Backend Services**: Must be accessible from both gateways
3. **TLS Certificates**: Each gateway may need its own certificate if using HTTPS

## Verification

Check if HTTPRoute is attached to multiple gateways:

```bash
kubectl get httproute <route-name> -n mailer -o jsonpath='{.spec.parentRefs[*].name}'
```

If it shows both gateway names, they're sharing the HTTPRoute.

## Final Answer

**Q: Can they share the same HTTPRoute?**

**A: Yes, but they currently don't.**

Currently:
- `gateway-test-nginx-http` serves `mailer2.kuprin.su` on `gateway-test-nginx`
- `mail-in-a-pods-test-routes-http` serves `mailer3.kuprin.su` on `mail-in-a-pods-gateway-test`

However, both LoadBalancers serve `mailer2.kuprin.su` because:
1. Both Gateway HTTP listeners have **no hostname restriction** (empty `hostname`)
2. This allows the Gateway to accept requests with any Host header
3. Cilium Gateway appears to route all traffic to the attached HTTPRoute regardless of HTTPRoute's hostname filter

**To make them share the same HTTPRoute**, add `mail-in-a-pods-gateway-test` to `gateway-test-nginx-http`'s `parentRefs`:

```bash
kubectl patch httproute gateway-test-nginx-http -n mailer --type json \
  -p='[{"op": "add", "path": "/spec/parentRefs/-", "value": {"name": "mail-in-a-pods-gateway-test", "sectionName": "http"}}]'
```

This will make `gateway-test-nginx-http` serve on both gateways, ensuring consistent routing.

