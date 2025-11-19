# Fix: mailer3.kuprin.su Not Working on Cilium Gateway

## Problem Summary

- `mailer3.kuprin.su` configured in HTTPRoute `mail-in-a-pods-test-routes-http`
- HTTPRoute is accepted and programmed by Cilium Gateway
- But requests with `Host: mailer3.kuprin.su` result in "Connection reset by peer"
- Meanwhile, `mailer2.kuprin.su` works even though there's no route for it

## Root Cause

**Cilium Gateway appears to have a bug or unexpected behavior with HTTPRoute hostname matching:**

1. When HTTPRoute has `hostnames: ["mailer3.kuprin.su"]`, requests matching that hostname are rejected
2. Requests with non-matching hostnames (`mailer2.kuprin.su`) work, suggesting the route is being used as a catch-all
3. This is the opposite of expected behavior

## Solution: Remove Hostname Restriction

Since Cilium Gateway seems to ignore/break hostname matching, remove the hostname restriction from the HTTPRoute:

```bash
kubectl patch httproute mail-in-a-pods-test-routes-http -n mailer --type json \
  -p='[{"op": "remove", "path": "/spec/hostnames"}]'
```

This will make the route accept **all hostnames**, which should fix `mailer3.kuprin.su`.

## Alternative: Add Multiple Hostnames

If you need to keep hostname matching, try adding both hostnames:

```bash
kubectl patch httproute mail-in-a-pods-test-routes-http -n mailer --type json \
  -p='[{"op": "replace", "path": "/spec/hostnames", "value": ["mailer2.kuprin.su", "mailer3.kuprin.su"]}]'
```

## Verification

After applying the fix:

```bash
# Should work
curl -v http://108.61.117.121/ -H "Host: mailer3.kuprin.su"

# Should also work
curl -v http://108.61.117.121/ -H "Host: mailer2.kuprin.su"
```

## Why This Happens

This appears to be a **Cilium Gateway implementation bug** where:
- HTTPRoute hostname matching is inverted or broken
- Routes with hostnames reject matching requests
- Routes without hostnames work as catch-all

This is different from NGINX Gateway Fabric behavior, which correctly enforces hostname matching.

## Long-term Solution

1. **Report the bug** to Cilium project
2. **Use NGINX Gateway Fabric** for hostname-based routing (more reliable)
3. **Use Cilium Gateway** only for routes without hostname restrictions

