# Diagnosing Host Header Routing Issue

## Problem

When adding a Host header to requests:
- **Port 80**: Request hangs and exits (timeout)
- **Port 10**: Connection reset by peer
- **Without Host header**: Fast 404 (expected behavior)

## Root Cause

The issue is **hostname matching** in HTTPRoute:

1. **HTTPRoute `mail-in-a-pods-http`** has `hostnames: - mailer4.kuprin.su` configured
2. When a Host header is provided that **doesn't match** the configured hostname:
   - NGINX Gateway tries to match the hostname against all HTTPRoutes
   - If no match is found, it may hang or timeout instead of returning a quick 404
   - This is a known behavior in some Gateway implementations

3. **Health route on port 10** works without Host header because:
   - It doesn't have hostname restrictions
   - It matches any request to that listener

## Solutions

### Solution 1: Add a Catch-All HTTPRoute (Recommended)

Create an HTTPRoute without hostname restrictions to handle unmatched hostnames:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mail-in-a-pods-catchall
  namespace: mailer
spec:
  parentRefs:
  - name: mail-in-a-pods-gateway
    sectionName: http
  rules:
  - backendRefs:
    - name: mail-in-a-pods-statics-server
      port: 80
      weight: 1
    # No hostnames specified = matches all hostnames
```

### Solution 2: Remove Hostname Restriction from Existing Route

If you want the route to accept any hostname:

```yaml
# Patch the HTTPRoute to remove hostname restriction
kubectl patch httproute mail-in-a-pods-http -n mailer --type json \
  -p='[{"op": "remove", "path": "/spec/hostnames"}]'
```

**Warning**: This will make the route accept requests for any hostname, which may not be desired for security.

### Solution 3: Add Wildcard Hostname

Add a wildcard hostname to match subdomains:

```yaml
spec:
  hostnames:
  - mailer4.kuprin.su
  - "*.kuprin.su"  # Matches any subdomain
```

### Solution 4: Configure Default Backend

Some Gateway implementations support a default backend for unmatched routes. Check if NGINX Gateway Fabric supports this via NginxProxy configuration.

## Why Port 10 Behaves Differently

The health route (`mail-in-a-pods-health`) on port 10:
- **No hostname restrictions** - matches any request
- **Works without Host header** - returns 200
- **Connection reset with Host header** - likely because:
  - The health listener might have different routing rules
  - Or NGINX is trying to match the Host header against routes and failing

## Testing

After applying a solution, test:

```bash
# Should work (matches configured hostname)
curl -v http://108.61.188.185:80/ -H "Host: mailer4.kuprin.su"

# Should now return 404 quickly (not hang)
curl -v http://108.61.188.185:80/ -H "Host: mailer4.kuprin.su2"

# Should work (no hostname restriction on health route)
curl -v http://108.61.188.185:10/

# Should also work with Host header (if catch-all route is added)
curl -v http://108.61.188.185:10/ -H "Host: mailer4.kuprin.su2"
```

## NGINX Gateway Fabric Behavior

NGINX Gateway Fabric:
- Matches HTTPRoutes based on hostname first
- If hostname matches, then matches path rules
- If no hostname match is found, behavior depends on configuration:
  - May return 404 immediately
  - May hang/timeout (your current issue)
  - May use a default backend if configured

The hanging behavior suggests NGINX is waiting for a route match that never comes, or there's a timeout issue in the routing logic.

## Recommended Fix

**Add a catch-all HTTPRoute** that handles unmatched hostnames and returns a proper 404 response quickly:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mail-in-a-pods-catchall
  namespace: mailer
spec:
  parentRefs:
  - name: mail-in-a-pods-gateway
    sectionName: http
  rules:
  - backendRefs:
    - name: mail-in-a-pods-statics-server
      port: 80
      weight: 1
    matches:
    - path:
        type: PathPrefix
        value: /
    # No hostnames = matches all hostnames not matched by other routes
```

This route will only be used if no other route matches the hostname, ensuring unmatched hostnames get a quick 404 response instead of hanging.

