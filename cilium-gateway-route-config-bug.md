# Cilium Gateway Bug: Route Config Not Applied to Listener

## Problem

- **Backend responds** when accessed directly
- **Envoy returns 404** when accessed via Gateway
- **HTTPRoute is accepted** by Cilium Gateway
- **Gateway shows route attached** (`attachedRoutes: 1`)
- **Virtual host exists** in RoutesConfigDump
- **But listener has no route configuration**

## Root Cause

The HTTP connection manager filter in the listener has:
```json
{
  "route_config": null,
  "rds": null
}
```

**This means Envoy has NO route configuration, even though:**
- Virtual host exists in RoutesConfigDump
- HTTPRoute is accepted
- Gateway shows route attached

## Why This Happens

1. **Cilium Gateway creates route config** ✅
   - Virtual host appears in `RoutesConfigDump`
   - Route configuration exists

2. **But doesn't configure listener to use it** ❌
   - Listener's HTTP connection manager has no `route_config`
   - Listener's HTTP connection manager has no `rds` (Route Discovery Service)
   - Envoy has no way to access the route config

3. **Result: Envoy can't match routes** ❌
   - All requests return 404
   - Virtual host exists but is orphaned

## Evidence

### Listener Configuration
```json
{
  "filter_chains": [{
    "filters": [{
      "name": "envoy.filters.network.http_connection_manager",
      "typed_config": {
        "route_config": null,  // ❌ No embedded routes
        "rds": null             // ❌ No RDS config
      }
    }]
  }]
}
```

### RoutesConfigDump
```json
{
  "virtual_hosts": [{
    "name": "mailer/cilium-gateway-mail-in-a-pods-gateway-test/mailer3.kuprin.su",
    "domains": ["mailer3.kuprin.su"],
    "routes": [...]
  }]
}
```

**The virtual host exists but is not connected to the listener!**

## This Explains Everything

- ✅ Backend responds (direct access works)
- ❌ Envoy returns 404 (no routes configured on listener)
- ✅ Virtual host exists (in RoutesConfigDump, but orphaned)
- ✅ HTTPRoute accepted (but not applied to listener)

## Solution

This is a **Cilium Gateway bug**. The route configuration is created but not applied to the listener.

### Possible Fixes

1. **Restart Cilium/Envoy**:
   ```bash
   kubectl rollout restart daemonset/cilium -n kube-system
   ```

2. **Recreate HTTPRoute**:
   ```bash
   kubectl delete httproute mail-in-a-pods-test-routes-http -n mailer
   # Then recreate it
   ```

3. **Recreate Gateway**:
   ```bash
   kubectl delete gateway mail-in-a-pods-gateway-test -n mailer
   # Then recreate it
   ```

4. **Check Cilium Gateway logs**:
   ```bash
   kubectl logs -n kube-system -l k8s-app=cilium --tail=100 | grep -i "route\|listener\|gateway"
   ```

5. **Report bug to Cilium**:
   - Route accepted but not applied to listener
   - route_config and rds both null in listener filter

## Verification

After fix, check that listener has route config:
```bash
jq '.configs[] | select(.["@type"] == "type.googleapis.com/envoy.admin.v3.ListenersConfigDump") | .dynamic_listeners[] | select(.name | contains("mail-in-a-pods-gateway-test")) | .active_state.listener.filter_chains[] | select(.filters[].name == "envoy.filters.network.http_connection_manager") | .filters[0].typed_config | {route_config: .route_config, rds: .rds}' envoy-config-dump.json
```

Should show either `route_config` with virtual_hosts or `rds` with config_source.


