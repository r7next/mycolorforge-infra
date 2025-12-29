# Cloudflare Tunnel Setup Script for ColorForge (PowerShell)
# Run this script after downloading cloudflared.exe

param(
    [string]$Domain = "mycolorforge.com",
    [string]$TunnelName = "colorforge"
)

$ErrorActionPreference = "Stop"
$Namespace = "colorforge"

Write-Host "=== Cloudflare Tunnel Setup for ColorForge ===" -ForegroundColor Cyan
Write-Host "Domain: $Domain"
Write-Host ""

# Check if cloudflared exists
$cloudflared = ".\cloudflared.exe"
if (-not (Test-Path $cloudflared)) {
    $cloudflared = "cloudflared.exe"
    if (-not (Get-Command $cloudflared -ErrorAction SilentlyContinue)) {
        Write-Host "Downloading cloudflared..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile "cloudflared.exe"
        $cloudflared = ".\cloudflared.exe"
    }
}

# Step 1: Login
Write-Host ""
Write-Host "=== Step 1: Login to Cloudflare ===" -ForegroundColor Cyan
Write-Host "This will open your browser for authentication..."
& $cloudflared tunnel login

# Step 2: Create tunnel
Write-Host ""
Write-Host "=== Step 2: Create Tunnel ===" -ForegroundColor Cyan

# Check if tunnel exists
$tunnels = & $cloudflared tunnel list --output json | ConvertFrom-Json
$existingTunnel = $tunnels | Where-Object { $_.name -eq $TunnelName }

if ($existingTunnel) {
    $TunnelId = $existingTunnel.id
    Write-Host "Using existing tunnel: $TunnelId"
} else {
    Write-Host "Creating new tunnel '$TunnelName'..."
    & $cloudflared tunnel create $TunnelName
    $tunnels = & $cloudflared tunnel list --output json | ConvertFrom-Json
    $TunnelId = ($tunnels | Where-Object { $_.name -eq $TunnelName }).id
}

Write-Host "Tunnel ID: $TunnelId" -ForegroundColor Green

# Step 3: Find credentials file
$CredsFile = Join-Path $env:USERPROFILE ".cloudflared\$TunnelId.json"
if (-not (Test-Path $CredsFile)) {
    Write-Host "Error: Credentials file not found at $CredsFile" -ForegroundColor Red
    exit 1
}

# Step 4: Create Kubernetes secret
Write-Host ""
Write-Host "=== Step 3: Create Kubernetes Secret ===" -ForegroundColor Cyan

$credsContent = Get-Content $CredsFile -Raw
kubectl create secret generic cloudflared-credentials `
    --namespace=$Namespace `
    --from-file=credentials.json=$CredsFile `
    --dry-run=client -o yaml | kubectl apply -f -

# Step 5: Update ConfigMap
Write-Host ""
Write-Host "=== Step 4: Update ConfigMap ===" -ForegroundColor Cyan

$configMapPath = Join-Path $PSScriptRoot "cloudflared-configmap.yaml"
$configContent = Get-Content $configMapPath -Raw
$configContent = $configContent -replace "TUNNEL_ID_PLACEHOLDER", $TunnelId
$configContent = $configContent -replace "mycolorforge.com", $Domain
$configContent | Set-Content $configMapPath

kubectl apply -f $configMapPath

# Step 6: Create DNS records
Write-Host ""
Write-Host "=== Step 5: Create DNS Records ===" -ForegroundColor Cyan

& $cloudflared tunnel route dns $TunnelName $Domain
& $cloudflared tunnel route dns $TunnelName "www.$Domain"
& $cloudflared tunnel route dns $TunnelName "api.$Domain"

# Step 7: Deploy cloudflared
Write-Host ""
Write-Host "=== Step 6: Deploy Cloudflared to Kubernetes ===" -ForegroundColor Cyan

kubectl apply -k $PSScriptRoot

# Wait for deployment
Write-Host ""
Write-Host "Waiting for cloudflared pods to be ready..."
kubectl wait --for=condition=ready pod -l app=cloudflared -n $Namespace --timeout=120s

Write-Host ""
Write-Host "=== Setup Complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Your services will be available at:" -ForegroundColor Cyan
Write-Host "  - https://$Domain (Frontend)"
Write-Host "  - https://www.$Domain (Frontend)"
Write-Host "  - https://api.$Domain (API)"
Write-Host ""
Write-Host "Check tunnel status:"
Write-Host "  kubectl logs -n $Namespace -l app=cloudflared -f"
Write-Host ""
Write-Host "Cloudflare Dashboard:"
Write-Host "  https://dash.cloudflare.com -> Zero Trust -> Access -> Tunnels"
