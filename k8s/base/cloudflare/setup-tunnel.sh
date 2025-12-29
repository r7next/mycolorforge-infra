#!/bin/bash
# Cloudflare Tunnel Setup Script for ColorForge
# Run this script after creating a tunnel via cloudflared CLI

set -e

NAMESPACE="colorforge"
DOMAIN="${1:-mycolorforge.com}"

echo "=== Cloudflare Tunnel Setup for ColorForge ==="
echo "Domain: $DOMAIN"
echo ""

# Check if cloudflared is installed
if ! command -v cloudflared &> /dev/null; then
    echo "Error: cloudflared is not installed"
    echo "Install from: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/"
    exit 1
fi

# Check if logged in
if ! cloudflared tunnel list &> /dev/null; then
    echo "Please login to Cloudflare first:"
    echo "  cloudflared tunnel login"
    exit 1
fi

# Check for existing tunnel or create new one
TUNNEL_NAME="colorforge"
TUNNEL_ID=$(cloudflared tunnel list --output json | jq -r ".[] | select(.name==\"$TUNNEL_NAME\") | .id")

if [ -z "$TUNNEL_ID" ]; then
    echo "Creating tunnel '$TUNNEL_NAME'..."
    cloudflared tunnel create $TUNNEL_NAME
    TUNNEL_ID=$(cloudflared tunnel list --output json | jq -r ".[] | select(.name==\"$TUNNEL_NAME\") | .id")
fi

echo "Tunnel ID: $TUNNEL_ID"

# Get credentials file path
CREDS_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"
if [ ! -f "$CREDS_FILE" ]; then
    echo "Error: Credentials file not found at $CREDS_FILE"
    exit 1
fi

echo ""
echo "=== Creating Kubernetes Secret ==="

# Create secret from credentials file
kubectl create secret generic cloudflared-credentials \
    --namespace=$NAMESPACE \
    --from-file=credentials.json="$CREDS_FILE" \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=== Updating ConfigMap with Tunnel ID ==="

# Update configmap with actual tunnel ID
sed -i "s/TUNNEL_ID_PLACEHOLDER/$TUNNEL_ID/g" cloudflared-configmap.yaml

# Also update domain if different
if [ "$DOMAIN" != "mycolorforge.com" ]; then
    sed -i "s/mycolorforge.com/$DOMAIN/g" cloudflared-configmap.yaml
fi

kubectl apply -f cloudflared-configmap.yaml

echo ""
echo "=== Creating DNS Records ==="

# Create DNS records pointing to the tunnel
cloudflared tunnel route dns $TUNNEL_NAME $DOMAIN
cloudflared tunnel route dns $TUNNEL_NAME www.$DOMAIN
cloudflared tunnel route dns $TUNNEL_NAME api.$DOMAIN

echo ""
echo "=== Deploying Cloudflared ==="
kubectl apply -k .

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Your services will be available at:"
echo "  - https://$DOMAIN (Frontend)"
echo "  - https://www.$DOMAIN (Frontend)"
echo "  - https://api.$DOMAIN (API)"
echo ""
echo "Check tunnel status:"
echo "  kubectl logs -n $NAMESPACE -l app=cloudflared -f"
echo ""
echo "Check Cloudflare dashboard:"
echo "  https://dash.cloudflare.com -> Zero Trust -> Access -> Tunnels"
