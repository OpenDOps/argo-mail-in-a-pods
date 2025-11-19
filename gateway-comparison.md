# Gateway Comparison: gateway-test-nginx vs mail-in-a-pods-gateway-test

## Overview

Comparing two gateways to understand why host resolution works on one but not the other.

## Gateway Comparison Table

| Feature | gateway-test-nginx | mail-in-a-pods-gateway-test |
|---------|-------------------|----------------------------|
| **Status** | ✅ Accepted & Programmed | ✅ Accepted & Programmed |
| **External IP** | ✅ 95.179.142.249 | ✅ 209.250.249.160 |
| **Gateway Class** | nginx | nginx |
| **Listeners** | HTTP (80), HTTPS (443) | HTTP (80), HTTPS (443) |
| **Hostname** | mailer2.kuprin.su | mailer3.kuprin.su |
| **Hostname Resolution** | ✅ Working | ❌ Not working |
| **HTTPRoute Hostname** | mailer2.kuprin.su | mailer3.kuprin.su |
| **HTTPS Listener Hostname** | mailer2.kuprin.su | mailer3.kuprin.su |
| **Certificate** | cafe-secret | cafe-secret |
| **Certificate Issuer** | letsencrypt-test-nginx | mail-in-a-pods-cert-issuer |

## gateway-test-nginx

### Configuration
- **Listeners**:
  - HTTP (port 80) - no hostname restriction
  - HTTPS (port 443) - hostname: `mailer2.kuprin.su`
- **TLS**: Uses `cafe-secret` for HTTPS
- **Certificate Management**: `letsencrypt-test-nginx` cluster issuer

### HTTPRoute
- **Name**: `gateway-test-nginx-http`
- **Hostnames**: `mailer2.kuprin.su` (specific)
- **Backend**: `mail-in-a-pods-statics-server:80`
- **Status**: ✅ Accepted on both http and https listeners

### Status
- ✅ **Accepted**: True
- ✅ **Programmed**: True
- ✅ **Address**: 95.179.142.249 (IPv4), 2001:19f0:5001:3526:ffff:ffff:ffff:ffff (IPv6)
- ✅ **Listeners**: Both accepted and programmed

## mail-in-a-pods-gateway-test

### Configuration
- **Listeners**:
  - HTTP (port 80) - no hostname restriction
  - HTTPS (port 443) - hostname: `mailer3.kuprin.su`
- **TLS**: Uses `cafe-secret` for HTTPS
- **Certificate Management**: `mail-in-a-pods-cert-issuer` cluster issuer
- **Status**: ✅ Accepted & Programmed
- **Address**: 209.250.249.160 (IPv4), 2a05:f480:1400:3d28:ffff:ffff:ffff:ffff (IPv6)

### HTTPRoute
- **Name**: `mail-in-a-pods-test-routes-http`
- **Hostnames**: `mailer3.kuprin.su` (specific)
- **Backend**: `mail-in-a-pods-statics-server:80`
- **Status**: ✅ Accepted on both http and https listeners

## Key Differences

### 1. Hostname Matching

**gateway-test-nginx**:
- HTTPRoute has specific hostname: `mailer2.kuprin.su`
- HTTPS listener has hostname restriction: `mailer2.kuprin.su`
- ✅ Hostname resolves correctly
- ✅ DNS points to: 95.179.142.249

**mail-in-a-pods-gateway-test**:
- HTTPRoute has specific hostname: `mailer3.kuprin.su`
- HTTPS listener has hostname restriction: `mailer3.kuprin.su`
- ❌ Hostname not resolving
- ❌ DNS likely not pointing to: 209.250.249.160

### 2. Certificate Issuer

**gateway-test-nginx**:
- Uses `letsencrypt-test-nginx` cluster issuer
- Certificate: `cafe-secret`

**mail-in-a-pods-gateway-test**:
- Uses `mail-in-a-pods-cert-issuer` cluster issuer
- Certificate: `cafe-secret` (same secret, different issuer)

### 2. Gateway Status

**gateway-test-nginx**:
- Fully accepted and programmed
- Has assigned external IP
- All listeners are active

**mail-in-a-pods-gateway-test**:
- Accepted and programmed
- Has assigned external IP
- Need to check listener status

## Root Cause: DNS Configuration Mismatch

**Critical Finding**: Both DNS records point to **different IPs** than the Gateway external IPs!

### gateway-test-nginx
- **Hostname**: `mailer2.kuprin.su`
- **Gateway External IP**: `95.179.142.249`
- **DNS Resolves To**: `198.18.1.190` ❌ **MISMATCH!**
- **Result**: DNS points to wrong IP, but may still work if there's routing/proxy

### mail-in-a-pods-gateway-test
- **Hostname**: `mailer3.kuprin.su`
- **Gateway External IP**: `209.250.249.160`
- **DNS Resolves To**: `198.18.1.191` ❌ **MISMATCH!**
- **Result**: DNS points to wrong IP, hostname doesn't resolve correctly

## The Problem

Both gateways have **DNS records pointing to different IPs** than their LoadBalancer external IPs:

| Gateway | Hostname | Gateway IP | DNS IP | Match |
|---------|----------|------------|--------|-------|
| gateway-test-nginx | mailer2.kuprin.su | 95.179.142.249 | 198.18.1.190 | ❌ No |
| mail-in-a-pods-gateway-test | mailer3.kuprin.su | 209.250.249.160 | 198.18.1.191 | ❌ No |

**Why one works and the other doesn't:**
- `mailer2.kuprin.su` (198.18.1.190) might have additional routing/proxy setup
- `mailer3.kuprin.su` (198.18.1.191) likely doesn't have routing to the Gateway

## Possible Causes for Hostname Resolution Issues

1. **DNS Not Configured**: No A/AAAA record for `mailer3.kuprin.su`
2. **Wrong DNS Record**: DNS points to different IP (not 209.250.249.160)
3. **DNS Propagation**: DNS changes not propagated yet
4. **Certificate Issues**: TLS certificate not issued for `mailer3.kuprin.su` (if using HTTPS)

## Diagnostic Steps

1. **Check HTTPRoute configuration**:
   ```bash
   kubectl get httproute -n mailer -o yaml | grep -A 20 "mail-in-a-pods-gateway-test"
   ```

2. **Check DNS resolution**:
   ```bash
   dig mailer2.kuprin.su  # Should resolve to 95.179.142.249
   dig mailer3.kuprin.su  # Should resolve to 209.250.249.160 (but likely doesn't)
   ```

3. **Check Gateway listener status**:
   ```bash
   kubectl get gateway mail-in-a-pods-gateway-test -n mailer -o jsonpath='{.status.listeners[*]}'
   ```

4. **Compare HTTPRoute hostnames**:
   - gateway-test-nginx: `mailer2.kuprin.su` ✅
   - mail-in-a-pods-gateway-test: `mailer3.kuprin.su` ✅ (configured correctly)

## Recommendations

1. ✅ **HTTPRoute exists** for mail-in-a-pods-gateway-test - `mail-in-a-pods-test-routes-http`
2. ✅ **Hostname configuration** is correct - `mailer3.kuprin.su` in both Gateway and HTTPRoute
3. ❌ **DNS records** need to be created/updated:
   - Create A record: `mailer3.kuprin.su` → `209.250.249.160`
   - Create AAAA record: `mailer3.kuprin.su` → `2a05:f480:1400:3d28:ffff:ffff:ffff:ffff` (if using IPv6)
4. **Verify certificate** is issued for `mailer3.kuprin.su` (check `cafe-secret`)

## Summary

**Both gateways are configured correctly**, but **both have DNS mismatches**:

| Gateway | Status | DNS IP | Gateway IP | Issue |
|---------|--------|--------|------------|-------|
| gateway-test-nginx | ✅ Works | 198.18.1.190 | 95.179.142.249 | DNS mismatch, but has routing |
| mail-in-a-pods-gateway-test | ❌ Doesn't work | 198.18.1.191 | 209.250.249.160 | DNS mismatch, no routing |

## Solutions

### Option 1: Fix DNS Records (Recommended)
Update DNS to point directly to Gateway external IPs:
- `mailer2.kuprin.su` → `95.179.142.249`
- `mailer3.kuprin.su` → `209.250.249.160`

### Option 2: Configure Routing/Proxy
If `198.18.1.190` and `198.18.1.191` are proxy/routing IPs:
- Ensure `198.18.1.190` routes to `95.179.142.249` (gateway-test-nginx)
- Ensure `198.18.1.191` routes to `209.250.249.160` (mail-in-a-pods-gateway-test)

### Option 3: Use IP Directly
Access gateways directly via their external IPs:
- `http://95.179.142.249/ -H "Host: mailer2.kuprin.su"`
- `http://209.250.249.160/ -H "Host: mailer3.kuprin.su"`

