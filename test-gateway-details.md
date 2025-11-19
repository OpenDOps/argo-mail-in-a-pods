# Gateway Test-Nginx Details

## Overview

**Gateway Name**: `gateway-test-nginx`  
**Namespace**: `mailer`  
**Gateway Class**: `nginx`  
**Status**: ✅ Accepted and Programmed  
**External IP**: `95.179.142.249` (IPv4), `2001:19f0:5001:3526:ffff:ffff:ffff:ffff` (IPv6)

## Configuration

### Listeners

1. **HTTP Listener (port 80)**
   - Name: `http`
   - Port: `80`
   - Protocol: `HTTP`
   - Status: ✅ Accepted, Programmed, ResolvedRefs
   - Attached Routes: `1`
   - Supported Kinds: HTTPRoute, GRPCRoute

2. **HTTPS Listener (port 443)**
   - Name: `https`
   - Port: `443`
   - Protocol: `HTTPS`
   - Hostname: `mailer2.kuprin.su`
   - TLS Mode: `Terminate`
   - Certificate: `cafe-secret` (Secret)
   - Status: ✅ Accepted, Programmed, ResolvedRefs
   - Attached Routes: `1`
   - Supported Kinds: HTTPRoute, GRPCRoute

### Annotations

- `cert-manager.io/cluster-issuer: letsencrypt-test-nginx` - Used for automatic certificate management

## Service

**Service Name**: `gateway-test-nginx-nginx`  
**Type**: `LoadBalancer`  
**Cluster IP**: `172.26.65.49`  
**External IPs**: 
- IPv4: `95.179.142.249`
- IPv6: `2001:19f0:5001:3526:ffff:ffff:ffff:ffff`
**Ports**:
- Port 80 → NodePort 30119
- Port 443 → NodePort 30688

## HTTPRoute

**Route Name**: `gateway-test-nginx-http`  
**Hostnames**: `mailer2.kuprin.su`  
**Parent Refs**:
- `gateway-test-nginx` (http listener)
- `gateway-test-nginx` (https listener)

**Backend**:
- Service: `mail-in-a-pods-statics-server`
- Port: `80`
- Weight: `1`

**Path Matching**:
- Type: `PathPrefix`
- Value: `/` (matches all paths)

**Status**: ✅ Accepted by both listeners

## Gateway Status

### Overall Status
- **Accepted**: ✅ True (Gateway is accepted)
- **Programmed**: ✅ True (Gateway is programmed)

### Listener Status

Both listeners show:
- ✅ **Accepted**: Listener is accepted
- ✅ **Programmed**: Listener is programmed
- ✅ **ResolvedRefs**: All references are resolved
- ⚠️ **Conflicted**: False (No conflicts, but status shows "False" which means no conflicts detected)

## Comparison with Main Gateway

| Feature | gateway-test-nginx | mail-in-a-pods-gateway |
|---------|-------------------|------------------------|
| Status | ✅ Accepted & Programmed | ⚠️ Waiting for controller |
| External IP | ✅ Assigned (95.179.142.249) | ✅ Assigned (108.61.188.185) |
| HTTPRoute Hostname | ✅ Specific (mailer2.kuprin.su) | ✅ Specific (mailer4.kuprin.su) |
| Catch-all Route | ❌ No | ❌ No |
| Host Header Issue | Unknown | ⚠️ Hangs with unmatched hostnames |

## Key Observations

1. **Working Gateway**: This gateway is fully functional and accepted by the controller
2. **Single HTTPRoute**: Has one HTTPRoute with specific hostname matching
3. **TLS Configuration**: Uses a Secret (`cafe-secret`) for TLS termination
4. **Certificate Management**: Configured with cert-manager for automatic certificate provisioning

## Potential Issues

Similar to the main gateway, this gateway may also experience issues with:
- **Unmatched hostnames**: Requests with Host headers that don't match `mailer2.kuprin.su` may hang
- **No catch-all route**: Missing a default route for unmatched hostnames

## Recommendations

1. **Test hostname matching**: Verify if unmatched hostnames cause the same hanging issue
2. **Add catch-all route**: Consider adding a catch-all HTTPRoute if needed
3. **Monitor behavior**: Check if this gateway behaves differently than the main gateway with unmatched hostnames

## Access Information

**HTTP Access**:
```bash
curl http://95.179.142.249/ -H "Host: mailer2.kuprin.su"
```

**HTTPS Access**:
```bash
curl https://95.179.142.249/ -H "Host: mailer2.kuprin.su"
```

**Test Unmatched Hostname**:
```bash
curl http://95.179.142.249/ -H "Host: mailer2.kuprin.su2"
# Check if this hangs like the main gateway
```

