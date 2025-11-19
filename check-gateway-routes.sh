#!/bin/bash
# Script to check the state of routes for the mailer gateway

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
GATEWAY_NAME="mail-in-a-pods-gateway"

echo "=== Gateway Routes Status Report ==="
echo ""

echo "=== 1. Gateway Status ==="
echo ""
kubectl get gateway $GATEWAY_NAME -n $NAMESPACE -o jsonpath='{.status}' | jq '.' 2>/dev/null || kubectl get gateway $GATEWAY_NAME -n $NAMESPACE -o yaml | grep -A 50 "status:"
echo ""

echo "=== 2. Gateway Listeners ==="
echo ""
kubectl get gateway $GATEWAY_NAME -n $NAMESPACE -o jsonpath='{range .spec.listeners[*]}{.name}{": "}{.protocol}{" port "}{.port}{"\n"}{end}'
echo ""

echo "=== 3. Gateway Listeners Status ==="
echo ""
kubectl get gateway $GATEWAY_NAME -n $NAMESPACE -o jsonpath='{range .status.listeners[*]}{.name}{":\n"}{"  Attached Routes: "}{.attachedRoutes}{"\n"}{"  Supported Kinds: "}{.supportedKinds[*].kind}{"\n"}{range .conditions[*]}{"  "}{.type}{": "}{.status}{" - "}{.reason}{" ("}{.message}{")\n"}{end}{end}'
echo ""

echo "=== 4. All HTTPRoutes in Namespace ==="
echo ""
kubectl get httproute -n $NAMESPACE -o custom-columns=NAME:.metadata.name,HOSTNAMES:.spec.hostnames[*],PARENT:.spec.parentRefs[*].name,STATUS:.status.parents[*].conditions[*].type
echo ""

echo "=== 5. HTTPRoutes Attached to Gateway ==="
echo ""
for route in $(kubectl get httproute -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    PARENT=$(kubectl get httproute $route -n $NAMESPACE -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
    if [[ "$PARENT" == *"$GATEWAY_NAME"* ]]; then
        echo "--- HTTPRoute: $route ---"
        echo "Hostnames: $(kubectl get httproute $route -n $NAMESPACE -o jsonpath='{.spec.hostnames[*]}')"
        echo "Parent Refs:"
        kubectl get httproute $route -n $NAMESPACE -o jsonpath='{range .spec.parentRefs[*]}{"  - "}{.name}{" ("}{.sectionName}{")\n"}{end}'
        echo "Status:"
        kubectl get httproute $route -n $NAMESPACE -o jsonpath='{range .status.parents[*]}{"  Controller: "}{.controllerName}{"\n"}{"  Parent: "}{.parentRef.name}{" ("}{.parentRef.sectionName}{")\n"}{range .conditions[*]}{"    "}{.type}{": "}{.status}{" - "}{.reason}{"\n"}{end}{end}'
        echo ""
    fi
done

echo "=== 6. HTTPRoute Backend Services ==="
echo ""
for route in $(kubectl get httproute -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    PARENT=$(kubectl get httproute $route -n $NAMESPACE -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
    if [[ "$PARENT" == *"$GATEWAY_NAME"* ]]; then
        echo "--- HTTPRoute: $route ---"
        echo "Backend Refs:"
        kubectl get httproute $route -n $NAMESPACE -o jsonpath='{range .spec.rules[*]}{range .backendRefs[*]}{"  - "}{.name}{":"}{.port}{" (weight: "}{.weight}{")\n"}{end}{end}'
        echo ""
    fi
done

echo "=== 7. Gateway Conditions Summary ==="
echo ""
kubectl get gateway $GATEWAY_NAME -n $NAMESPACE -o jsonpath='{range .status.conditions[*]}{.type}{": "}{.status}{" - "}{.reason}{" ("}{.message}{")\n"}{end}'
echo ""

echo "=== 8. Route Acceptance Status ==="
echo ""
echo "Routes accepted by controllers:"
for route in $(kubectl get httproute -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    PARENT=$(kubectl get httproute $route -n $NAMESPACE -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
    if [[ "$PARENT" == *"$GATEWAY_NAME"* ]]; then
        ACCEPTED=$(kubectl get httproute $route -n $NAMESPACE -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "Unknown")
        echo "  $route: $ACCEPTED"
    fi
done
echo ""

echo "=== 9. Gateway Class ==="
echo ""
GATEWAY_CLASS=$(kubectl get gateway $GATEWAY_NAME -n $NAMESPACE -o jsonpath='{.spec.gatewayClassName}')
echo "Gateway Class: $GATEWAY_CLASS"
kubectl get gatewayclass $GATEWAY_CLASS -o jsonpath='{.status.conditions[*].type}{": "}{.status.conditions[*].status}{"\n"}' 2>/dev/null || echo "GatewayClass not found"
echo ""

