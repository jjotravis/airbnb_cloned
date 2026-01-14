#!/bin/bash

# Airbnb Clone - Deployment Script
# This script automates the complete deployment process

set -e

echo "========================================"
echo "Airbnb Clone - Azure Deployment Script"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
print_info "Checking prerequisites..."

command -v az >/dev/null 2>&1 || { print_error "Azure CLI is required but not installed. Aborting."; exit 1; }
command -v terraform >/dev/null 2>&1 || { print_error "Terraform is required but not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is required but not installed. Aborting."; exit 1; }
command -v docker >/dev/null 2>&1 || { print_error "Docker is required but not installed. Aborting."; exit 1; }

print_info "All prerequisites met!"

# Check Azure login
print_info "Checking Azure login status..."
if ! az account show &>/dev/null; then
    print_warning "Not logged in to Azure. Initiating login..."
    az login
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
print_info "Using Azure subscription: $SUBSCRIPTION_ID"

# Step 1: Provision Infrastructure with Terraform
print_info "Step 1/6: Provisioning Azure infrastructure with Terraform..."

cd terraform

# Initialize Terraform
print_info "Initializing Terraform..."
terraform init

# Validate configuration
print_info "Validating Terraform configuration..."
terraform validate

# Plan infrastructure
print_info "Planning infrastructure changes..."
terraform plan -out=tfplan

# Apply infrastructure
read -p "Do you want to apply the Terraform plan? (yes/no): " apply_answer
if [ "$apply_answer" = "yes" ]; then
    print_info "Applying Terraform configuration..."
    terraform apply tfplan
    
    # Get outputs
    print_info "Retrieving Terraform outputs..."
    ACR_NAME=$(terraform output -raw acr_login_server | cut -d'.' -f1)
    ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)
    AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
    RESOURCE_GROUP=$(terraform output -raw resource_group_name)
    COSMOSDB_CONNECTION_STRING=$(terraform output -raw cosmosdb_connection_string)
    
    print_info "ACR Name: $ACR_NAME"
    print_info "AKS Cluster: $AKS_CLUSTER_NAME"
    print_info "Resource Group: $RESOURCE_GROUP"
    
    # Create NSG rule for API port 4000
    print_info "Creating NSG rule for API port 4000..."
    NSG_NAME="airbnb-clone-nsg"
    az network nsg rule create \
      --resource-group $RESOURCE_GROUP \
      --nsg-name $NSG_NAME \
      --name AllowAPIPort \
      --priority 103 \
      --direction Inbound \
      --access Allow \
      --protocol Tcp \
      --source-address-prefixes '*' \
      --source-port-ranges '*' \
      --destination-address-prefixes '*' \
      --destination-port-ranges 4000 2>/dev/null || print_warning "NSG rule already exists or failed to create"
else
    print_warning "Terraform apply skipped. Exiting..."
    exit 0
fi

cd ..

# Step 2: Build and Push Docker Images
print_info "Step 2/6: Building and pushing Docker images to ACR..."

# Login to ACR
print_info "Logging in to Azure Container Registry..."
az acr login --name $ACR_NAME

# Build and push API image
print_info "Building API Docker image..."
cd api
docker build -t $ACR_LOGIN_SERVER/airbnb-api:latest .
print_info "Pushing API image to ACR..."
docker push $ACR_LOGIN_SERVER/airbnb-api:latest
cd ..

# Build and push Client image
print_info "Building Client Docker image..."
cd client
docker build --no-cache -t $ACR_LOGIN_SERVER/airbnb-client:latest .
print_info "Pushing Client image to ACR..."
docker push $ACR_LOGIN_SERVER/airbnb-client:latest
cd ..

# Step 3: Configure kubectl
print_info "Step 3/6: Configuring kubectl for AKS..."
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --overwrite-existing

# Verify connection
print_info "Verifying AKS connection..."
kubectl cluster-info

# Step 4: Update Kubernetes manifests
print_info "Step 4/6: Updating Kubernetes manifests..."

# Update API deployment with ACR name
sed -i "s|REPLACE_WITH_ACR_NAME|$ACR_NAME|g" k8s/api-deployment.yaml
sed -i "s|REPLACE_WITH_ACR_NAME|$ACR_NAME|g" k8s/client-deployment.yaml

# Update secrets with Cosmos DB connection string
sed -i "s|REPLACE_WITH_COSMOSDB_CONNECTION_STRING|$COSMOSDB_CONNECTION_STRING|g" k8s/secrets.yaml

# Step 5: Deploy to Kubernetes
print_info "Step 5/6: Deploying application to AKS..."

# Apply namespace
kubectl apply -f k8s/namespace.yaml

# Apply secrets and config
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/configmap.yaml

# Deploy applications
kubectl apply -f k8s/api-deployment.yaml
kubectl apply -f k8s/client-deployment.yaml

# Wait for deployments
print_info "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/airbnb-api -n airbnb-clone
kubectl wait --for=condition=available --timeout=300s deployment/airbnb-client -n airbnb-clone

# Step 6: Get application URLs
print_info "Step 6/6: Retrieving application URLs..."

print_info "Waiting for LoadBalancer IPs..."
sleep 45

CLIENT_IP=$(kubectl get svc airbnb-client-service -n airbnb-clone -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
API_IP=$(kubectl get svc airbnb-api-service -n airbnb-clone -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$CLIENT_IP" ] || [ -z "$API_IP" ]; then
    print_warning "LoadBalancer IPs not yet assigned. Run these commands to get them later:"
    echo "kubectl get svc airbnb-client-service -n airbnb-clone"
    echo "kubectl get svc airbnb-api-service -n airbnb-clone"
    print_warning "After getting IPs, update ConfigMap and client nginx.conf manually."
else
    print_info "Client IP: $CLIENT_IP"
    print_info "API IP: $API_IP"
    
    # Update client nginx.conf with actual API IP
    print_info "Updating client nginx proxy configuration..."
    sed -i "s|proxy_pass http://.*:4000/;|proxy_pass http://$API_IP:4000/;|g" client/nginx.conf
    
    # Rebuild and push client with updated nginx config
    print_info "Rebuilding client with updated nginx config..."
    cd client
    docker build --no-cache -t $ACR_LOGIN_SERVER/airbnb-client:latest .
    docker push $ACR_LOGIN_SERVER/airbnb-client:latest
    cd ..
    # Update ConfigMap with correct URLs and cookie settings
    kubectl patch configmap airbnb-config -n airbnb-clone --type merge -p "{\"data\":{\"CLIENT_URL\":\"http://$CLIENT_IP\",\"API_URL\":\"http://$API_IP:4000\",\"ALLOWED_ORIGINS\":\"http://$CLIENT_IP,http://localhost:5173\",\"COOKIE_SECURE\":\"false\",\"COOKIE_SAMESITE\":\"lax\"}}"
    
    # Restart deployments to pick up new config and images
    kubectl rollout restart deployment/airbnb-api -n airbnb-clone
    kubectl rollout restart deployment/airbnb-client -n airbnb-clone
    
    print_info "Waiting for pods to restart..."
    sleep 20
    
    print_info "==============================================="
    print_info "Deployment completed successfully!"
    print_info "==============================================="
    print_info "Application URL: http://$CLIENT_IP"
    print_info "API URL: http://$API_IP:4000"
    print_info "==============================================="
    print_info "Note: For HTTPS deployment, update ConfigMap:"
    print_info "  COOKIE_SECURE=true"
    print_info "  COOKIE_SAMESITE=none"
    print_info "  ALLOWED_ORIGINS=https://your-domain.com"
    print_info "==============================================="
fi

# Display pod status
print_info "Current pod status:"
kubectl get pods -n airbnb-clone

print_info "Deployment script completed!"
