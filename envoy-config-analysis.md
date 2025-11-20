# Envoy Config Analysis: Routing to NodePort 30250 and Hostname Limitations

## Summary

From the Envoy config dump analysis:

### Virtual Host Configuration

**Virtual Host Name**: `mailer/cilium-gateway-mail-in-a-pods-gateway-test/mailer3.kuprin.su`

**Domains**:
- `mailer3.kuprin.su`
- `mailer3.kuprin.su:*`

**Routes**:
- Path: `/` (prefix match)
- Cluster: `mailer/cilium-gateway-mail-in-a-pods-gateway-test/mailer:mail-in-a-pods-statics-server:80`

## Hostname Limitation

### Key Finding

**Only `mailer3.kuprin.su` is configured in the virtual host domains.**

This means:
1. ✅ Requests with `Host: mailer3.kuprin.su` will match this virtual host
2. ❌ Requests with `Host: mailer2.kuprin.su` will NOT match this virtual host
3. ❌ Requests with any other hostname will NOT match

### Why This Causes Issues

When a request comes with a hostname that doesn't match:
- Envoy looks for a matching virtual host
- If no match is found, Envoy may:
  - Return 404 (if there's a default/catch-all route)
  - Reset the connection (if no default route exists)
  - Hang/timeout (implementation-specific behavior)

## Routing to NodePort 30250

### Cluster Configuration

The cluster `mailer/cilium-gateway-mail-in-a-pods-gateway-test/mailer:mail-in-a-pods-statics-server:80` routes to:
- Service: `mail-in-a-pods-statics-server`
- Port: `80`
- Namespace: `mailer`

### How NodePort 30250 is Used

NodePort 30250 is likely:
1. The NodePort assigned to the `mail-in-a-pods-statics-server` service
2. Used by the LoadBalancer to route traffic to the service
3. Not directly configured in Envoy (Envoy routes to ClusterIP, Kubernetes handles NodePort)

## Recommendations

### To Fix Hostname Matching Issues

1. **Add catch-all virtual host** (if supported by Cilium Gateway):
   - Create a virtual host with no domain restrictions
   - Route unmatched hostnames to a default backend

2. **Add all required hostnames**:
   - Add `mailer2.kuprin.su` to the HTTPRoute hostnames
   - Or create separate HTTPRoutes for each hostname

3. **Remove hostname restriction**:
   - Remove `hostnames` from the HTTPRoute spec
   - This makes the route accept all hostnames

### Current Configuration Issue

The Envoy config shows:
- **Only one virtual host**: `mailer3.kuprin.su`
- **Strict hostname matching**: Only exact match works
- **No catch-all route**: Unmatched hostnames have no route

This explains why:
- `mailer3.kuprin.su` should work (but doesn't due to other issues)
- `mailer2.kuprin.su` works (likely has a different route/virtual host)
- Other hostnames fail (no matching virtual host)

## Next Steps

1. Check if there are other virtual hosts in the config
2. Verify the cluster endpoints are correctly configured
3. Check if NodePort 30250 is the actual service port or if it's a different port
4. Consider adding a catch-all HTTPRoute without hostname restrictions


