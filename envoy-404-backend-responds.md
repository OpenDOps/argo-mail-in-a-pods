# Envoy 404 When Backend Responds - Root Cause Analysis

## Problem

- **Backend responds** when accessed directly
- **Envoy returns 404** when accessed via Gateway ClusterIP with `Host: mailer3.kuprin.su`
- Virtual host exists in config dump
- Cluster has healthy endpoints

## Analysis

### Virtual Host Configuration

From config dump:
```json
{
  "name": "mailer/cilium-gateway-mail-in-a-pods-gateway-test/mailer3.kuprin.su",
  "domains": ["mailer3.kuprin.su", "mailer3.kuprin.su:*"],
  "routes": [{
    "match": {"prefix": "/"},
    "cluster": "mailer/cilium-gateway-mail-in-a-pods-gateway-test/mailer:mail-in-a-pods-statics-server:80"
  }]
}
```

### Why 404?

If backend responds but Envoy returns 404, the issue is **virtual host matching failure**:

1. **Request reaches Envoy** ✅ (we see `server: envoy` in response)
2. **Host header is sent** ✅ (`Host: mailer3.kuprin.su`)
3. **Virtual host exists** ✅ (in RoutesConfigDump)
4. **But virtual host doesn't match** ❌

## Possible Causes

### 1. Virtual Host Not Active on Listener

The virtual host might exist in `RoutesConfigDump` but not be attached to the listener's filter chain.

**Check**: Is the virtual host in the listener's HTTP connection manager filter?

### 2. Host Header Mismatch

Envoy domain matching is strict:
- Case-sensitive
- No trailing dots
- Must match exactly (unless wildcard)

**Check**: Is `Host: mailer3.kuprin.su` exactly matching `mailer3.kuprin.su`?

### 3. Route Config Not Applied

The route configuration might exist but not be active on the listener.

**Check**: Is the route config actually being used by the listener?

### 4. Filter Chain Issue

There might be a filter chain mismatch preventing the virtual host from being matched.

## Debugging Steps

### 1. Check Listener Filter Chain

```bash
jq '.configs[] | select(.["@type"] == "type.googleapis.com/envoy.admin.v3.ListenersConfigDump") | .dynamic_listeners[] | select(.name | contains("mail-in-a-pods-gateway-test")) | .active_state.listener.filter_chains[] | select(.filters[].name == "envoy.filters.network.http_connection_manager") | .filters[0].typed_config.route_config.virtual_hosts[]' envoy-config-dump.json
```

If this returns empty, the virtual host is NOT attached to the listener.

### 2. Check Route Config Source

```bash
jq '.configs[] | select(.["@type"] == "type.googleapis.com/envoy.admin.v3.RoutesConfigDump") | .dynamic_route_configs[] | .route_config.name' envoy-config-dump.json
```

### 3. Test Host Header Variations

```bash
# Test exact match
curl http://172.26.4.210/ -H "Host: mailer3.kuprin.su"

# Test with port
curl http://172.26.4.210/ -H "Host: mailer3.kuprin.su:80"

# Test without Host header
curl http://172.26.4.210/
```

### 4. Check Envoy Logs

```bash
kubectl logs -n kube-system -l k8s-app=cilium-envoy --tail=100 | grep -i "mailer3\|404\|virtual"
```

## Most Likely Cause

**Virtual host exists in route config but is NOT attached to the listener's filter chain.**

This would explain:
- ✅ Virtual host exists (in RoutesConfigDump)
- ✅ Backend responds (direct access works)
- ❌ Envoy returns 404 (virtual host not matched on listener)

## Solution

If virtual host is not in listener filter chain:

1. **Check HTTPRoute status** - Is it accepted and programmed?
2. **Check Gateway status** - Is the route attached?
3. **Restart Cilium/Envoy** - Force config reload
4. **Check Cilium Gateway logs** - Look for route configuration errors

## Verification

The key check is whether the virtual host appears in:
- ✅ RoutesConfigDump (exists)
- ❓ Listener filter chain (needs verification)

If it's not in the listener filter chain, that's the root cause.


