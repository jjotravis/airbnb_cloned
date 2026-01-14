# Azure Deployment Guide - Airbnb Clone

Complete step-by-step guide to deploy the Airbnb Clone application on Azure using Terraform and AKS.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Azure Infrastructure Setup](#azure-infrastructure-setup)
3. [Build and Push Docker Images](#build-and-push-docker-images)
4. [Kubernetes Deployment](#kubernetes-deployment)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools
- Azure CLI (version 2.0+)
- Terraform (version 1.0+)
- Docker
- kubectl
- Git

### Azure Requirements
- Active Azure subscription
- Sufficient permissions to create resources
- Azure CLI authenticated

## Azure Infrastructure Setup

### Step 1: Authenticate with Azure

```bash
# Login to Azure
az login

# List available subscriptions
az account list --output table

# Set your subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Verify current subscription
az account show
```

### Step 2: Configure Terraform Variables

```bash
cd terraform

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

Update the following in `terraform.tfvars`:
```hcl
location            = "East US"  # Choose your Azure region
environment         = "prod"
project_name        = "airbnb-clone"
resource_group_name = "airbnb-clone-rg"

# Generate secure secrets
jwt_secret     = "your-secure-jwt-secret-min-32-chars"
session_secret = "your-secure-session-secret-min-32-chars"

# Optional: Cloudinary credentials for image uploads
cloudinary_name       = "your-cloudinary-name"
cloudinary_api_key    = "your-api-key"
cloudinary_api_secret = "your-api-secret"
```

### Step 3: Initialize Terraform

```bash
# Initialize Terraform (download providers)
terraform init

# Format configuration files
terraform fmt -recursive

# Validate configuration
terraform validate
```

### Step 4: Plan Infrastructure

```bash
# Review what will be created
terraform plan

# Save plan to file (optional)
terraform plan -out=tfplan
```

Expected resources:
- 1 Resource Group
- 1 Virtual Network with 3 subnets
- 2 Network Security Groups
- 1 Azure Container Registry
- 1 Cosmos DB account (MongoDB API)
- 1 AKS cluster with 2 nodes

### Step 5: Deploy Infrastructure

```bash
# Apply the configuration
terraform apply

# Or use saved plan
terraform apply tfplan
```

This will take approximately **10-15 minutes**.

### Step 6: Save Outputs

```bash
# View all outputs
terraform output

# Save specific outputs
terraform output -raw acr_login_server > ../acr_server.txt
terraform output -raw aks_cluster_name > ../aks_name.txt
terraform output -raw cosmosdb_connection_string > ../cosmos_connection.txt
```

## Build and Push Docker Images

### Step 1: Connect to Azure Container Registry

```bash
cd ..

# Get ACR name
ACR_NAME=$(terraform -chdir=terraform output -raw acr_name)

# Login to ACR
az acr login --name $ACR_NAME

# Get login server
ACR_SERVER=$(terraform -chdir=terraform output -raw acr_login_server)
echo "ACR Server: $ACR_SERVER"
```

### Step 2: Build and Push API Image

```bash
# Build API image
docker build -t $ACR_SERVER/airbnb-api:latest ./api

# Push to ACR
docker push $ACR_SERVER/airbnb-api:latest

# Verify
az acr repository list --name $ACR_NAME --output table
```

### Step 3: Build and Push Client Image

```bash
# Build client image
docker build -t $ACR_SERVER/airbnb-client:latest ./client

# Push to ACR
docker push $ACR_SERVER/airbnb-client:latest

# Verify both images
az acr repository show-tags --name $ACR_NAME --repository airbnb-api --output table
az acr repository show-tags --name $ACR_NAME --repository airbnb-client --output table
```

## Kubernetes Deployment

### Step 1: Connect to AKS Cluster

```bash
# Get AKS credentials
AKS_NAME=$(terraform -chdir=terraform output -raw aks_cluster_name)
RG_NAME=$(terraform -chdir=terraform output -raw resource_group_name)

az aks get-credentials --resource-group $RG_NAME --name $AKS_NAME --overwrite-existing

# Verify connection
kubectl get nodes
```

Expected output:
```
NAME                                STATUS   ROLES   AGE   VERSION
aks-default-xxxxx-vmss000000        Ready    agent   5m    v1.27.x
aks-default-xxxxx-vmss000001        Ready    agent   5m    v1.27.x
```

### Step 2: Create Kubernetes Secrets

```bash
# Get Cosmos DB connection string
COSMOS_CONNECTION=$(terraform -chdir=terraform output -raw cosmosdb_connection_string)

# Create namespace
kubectl create namespace airbnb-clone

# Create secrets
kubectl create secret generic airbnb-secrets \
  --from-literal=db-url="$COSMOS_CONNECTION" \
  --from-literal=jwt-secret="your-jwt-secret-here" \
  --from-literal=session-secret="your-session-secret-here" \
  --from-literal=cloudinary-name="your-cloudinary-name" \
  --from-literal=cloudinary-api-key="your-api-key" \
  --from-literal=cloudinary-api-secret="your-api-secret" \
  --namespace airbnb-clone

# Verify
kubectl get secrets -n airbnb-clone
```

### Step 3: Deploy Application to Kubernetes

Create Kubernetes manifests (next section will show the files).

```bash
# Apply all manifests
kubectl apply -f k8s/ -n airbnb-clone

# Watch deployment progress
kubectl get pods -n airbnb-clone -w
```

### Step 4: Expose Application

```bash
# Get LoadBalancer IP (may take 2-3 minutes)
kubectl get service airbnb-frontend -n airbnb-clone

# Wait for EXTERNAL-IP
kubectl get service airbnb-frontend -n airbnb-clone --watch
```

## Verification

### Check Application Status

```bash
# Check all resources
kubectl get all -n airbnb-clone

# Check pod logs
kubectl logs -l app=airbnb-api -n airbnb-clone --tail=50
kubectl logs -l app=airbnb-client -n airbnb-clone --tail=50

# Check pod details
kubectl describe pod <pod-name> -n airbnb-clone
```

### Access the Application

```bash
# Get frontend URL
FRONTEND_IP=$(kubectl get service airbnb-frontend -n airbnb-clone -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Application URL: http://$FRONTEND_IP:5173"

# Open in browser
xdg-open "http://$FRONTEND_IP:5173"  # Linux
open "http://$FRONTEND_IP:5173"       # macOS
```

### Test Database Connection

```bash
# Exec into API pod
API_POD=$(kubectl get pod -l app=airbnb-api -n airbnb-clone -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $API_POD -n airbnb-clone -- sh

# Inside the pod, test connection
node -e "require('mongoose').connect(process.env.DB_URL).then(() => console.log('Connected!')).catch(console.error)"
```

## Troubleshooting

### Common Issues

#### 1. Terraform Apply Fails

```bash
# Check Azure CLI authentication
az account show

# Re-authenticate if needed
az login

# Check resource quotas
az vm list-usage --location "East US" --output table
```

#### 2. Docker Push Fails

```bash
# Re-login to ACR
az acr login --name $ACR_NAME --expose-token

# Check ACR permissions
az acr show --name $ACR_NAME --query "adminUserEnabled"
```

#### 3. Pods Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name> -n airbnb-clone

# Check if images are pulled
kubectl get pods -n airbnb-clone -o jsonpath='{.items[*].status.containerStatuses[*].imageID}'

# Check ACR integration
kubectl get pods -n airbnb-clone -o jsonpath='{.items[*].status.containerStatuses[*].state}'
```

#### 4. Database Connection Issues

```bash
# Verify Cosmos DB is accessible
COSMOS_ENDPOINT=$(terraform -chdir=terraform output cosmosdb_endpoint)
az cosmosdb show --name <cosmos-account-name> --resource-group $RG_NAME

# Check secret
kubectl get secret airbnb-secrets -n airbnb-clone -o jsonpath='{.data.db-url}' | base64 -d
```

### Cleanup

To destroy all resources:

```bash
# Delete Kubernetes resources first
kubectl delete namespace airbnb-clone

# Destroy Terraform infrastructure
cd terraform
terraform destroy

# Confirm when prompted
```

## Cost Monitoring

```bash
# Check resource costs
az consumption usage list --start-date 2024-01-01 --end-date 2024-01-31

# Set up cost alerts (optional)
az consumption budget create \
  --resource-group $RG_NAME \
  --budget-name airbnb-monthly-budget \
  --amount 300 \
  --time-grain Monthly
```

## Next Steps

1. Set up CI/CD pipeline (GitHub Actions)
2. Configure custom domain
3. Enable HTTPS with Let's Encrypt
4. Set up monitoring with Azure Monitor
5. Configure autoscaling
6. Implement backup strategy

## Support

For issues:
1. Check pod logs: `kubectl logs <pod-name> -n airbnb-clone`
2. Check Azure portal for resource status
3. Review Terraform state: `terraform show`
4. Check AKS diagnostics in Azure portal
