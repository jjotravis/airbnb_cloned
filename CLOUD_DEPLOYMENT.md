# Airbnb Clone - Cloud Deployment Guide (Azure AKS)

[![Azure](https://img.shields.io/badge/Azure-0089D6?style=for-the-badge&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com)

This document covers deploying the Airbnb Clone application to Microsoft Azure using Kubernetes (AKS), Infrastructure as Code (Terraform), and CI/CD automation.

---

## 📋 Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start Deployment](#quick-start-deployment)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [Configuration](#configuration)
6. [Management & Operations](#management--operations)
7. [Troubleshooting](#troubleshooting)
8. [CI/CD Pipeline](#cicd-pipeline)

---

## 🏗️ Architecture Overview

### Cloud Infrastructure

```
Internet Users
    ↓
Azure Load Balancer (Public IP)
    ↓
Azure Kubernetes Service (AKS)
├─ Frontend Pods (React + Nginx) x2
├─ Backend API Pods (Node.js) x2
└─ Azure Container Registry (Private)
    ↓
Azure Cosmos DB (MongoDB API)
```

### Services Deployed

| Service | Purpose | Configuration |
|---------|---------|----------------|
| **AKS** | Container orchestration | 2 nodes (Standard_B2s) |
| **ACR** | Private container registry | Standard SKU |
| **Cosmos DB** | Managed MongoDB database | 400 RU/s, Session consistency |
| **Virtual Network** | Network isolation | 10.0.0.0/16 address space |
| **Load Balancer** | Traffic distribution | Standard SKU |

---

## ✅ Prerequisites

### Required Tools

Install these tools before deployment:

```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az --version

# Terraform
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform --version

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Docker
docker --version
```

### Azure Account Setup

```bash
# Login to Azure
az login

# View subscriptions
az account list --output table

# Set active subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Verify
az account show
```

### Check Quotas

```bash
# Verify you have quota for resources in your region
az vm list-usage --location westeurope --output table
```

---

## 🚀 Quick Start Deployment

The fastest way to deploy everything in one command:

```bash
# Navigate to project root
cd /path/to/Project

# Make deployment script executable (if not already)
chmod +x deploy.sh

# Run automated deployment
./deploy.sh
```

**What this script does:**
1. ✅ Initializes Terraform
2. ✅ Provisions Azure infrastructure (10-15 min)
3. ✅ Builds and pushes Docker images (5-10 min)
4. ✅ Configures kubectl for AKS
5. ✅ Deploys to Kubernetes (2-5 min)
6. ✅ Displays application URL

**Total time: ~20-30 minutes**

---

## 📋 Step-by-Step Deployment

### Step 1: Provision Infrastructure with Terraform

```bash
cd terraform

# Initialize Terraform (download providers)
terraform init

# Validate configuration
terraform validate

# Plan infrastructure changes
terraform plan -out=tfplan

# Review plan and apply
terraform apply tfplan
```

**What gets created:**
- Resource Group
- Virtual Network (10.0.0.0/16)
- AKS Cluster (2 nodes, Kubernetes 1.28)
- Container Registry (Standard)
- Cosmos DB Account + Database
- Network Security Groups
- Role Assignments

**Wait for completion** (10-15 minutes)

### Step 2: Capture Infrastructure Outputs

```bash
# View all outputs
terraform output

# Save specific values
ACR_NAME=$(terraform output -raw acr_login_server | cut -d'.' -f1)
ACR_SERVER=$(terraform output -raw acr_login_server)
AKS_CLUSTER=$(terraform output -raw aks_cluster_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
COSMOSDB_CONN=$(terraform output -raw cosmosdb_connection_string)

# Verify
echo "ACR Name: $ACR_NAME"
echo "AKS Cluster: $AKS_CLUSTER"
echo "Resource Group: $RESOURCE_GROUP"
```

**Save these values** - you'll need them for deployment!

### Step 3: Build Docker Images

```bash
# Navigate to project root
cd ..

# Login to Azure Container Registry
az acr login --name $ACR_NAME

# Build and push API image
cd airbnb-clone/api
docker build -t $ACR_SERVER/airbnb-api:latest .
docker push $ACR_SERVER/airbnb-api:latest

# Build and push Client image
cd ../client
docker build -t $ACR_SERVER/airbnb-client:latest .
docker push $ACR_SERVER/airbnb-client:latest

# Verify images in ACR
az acr repository list --name $ACR_NAME --output table
```

**Expected output:**
- airbnb-api (with latest tag)
- airbnb-client (with latest tag)

### Step 4: Configure kubectl

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER \
  --overwrite-existing

# Verify connection
kubectl cluster-info
kubectl get nodes
```

**Expected output:** 2 nodes in "Ready" state

### Step 5: Update Kubernetes Manifests

```bash
cd /path/to/Project/airbnb-clone/k8s

# Replace ACR name in manifests
sed -i "s|REPLACE_WITH_ACR_NAME|$ACR_NAME|g" api-deployment.yaml
sed -i "s|REPLACE_WITH_ACR_NAME|$ACR_NAME|g" client-deployment.yaml

# Replace Cosmos DB connection string
sed -i "s|REPLACE_WITH_COSMOSDB_CONNECTION_STRING|$COSMOSDB_CONN|g" secrets.yaml

# Verify changes
grep -i "acr\|cosmos" *.yaml
```

### Step 6: Deploy to Kubernetes

```bash
# Create namespace
kubectl apply -f namespace.yaml

# Create secrets and config
kubectl apply -f secrets.yaml
kubectl apply -f configmap.yaml

# Deploy applications
kubectl apply -f api-deployment.yaml
kubectl apply -f client-deployment.yaml

# Monitor deployment
kubectl get pods -n airbnb-clone -w
```

**Wait until all pods show "Running" status** (2-5 minutes)

### Step 7: Verify Deployment

```bash
# Check all resources
kubectl get all -n airbnb-clone

# Check pod status
kubectl get pods -n airbnb-clone -o wide

# View logs
kubectl logs -n airbnb-clone -l app=airbnb-api --tail=20
kubectl logs -n airbnb-clone -l app=airbnb-client --tail=20
```

### Step 8: Get Application URL

```bash
# Wait for LoadBalancer IP assignment
kubectl get svc airbnb-client-service -n airbnb-clone -w

# Once you have External IP:
CLIENT_IP=$(kubectl get svc airbnb-client-service -n airbnb-clone \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Application URL: http://$CLIENT_IP"
```

### Step 9: Update Configuration

```bash
# Update API with correct client URL
kubectl patch configmap airbnb-config -n airbnb-clone \
  --type merge \
  -p "{\"data\":{\"CLIENT_URL\":\"http://$CLIENT_IP\"}}"

# Restart API deployment
kubectl rollout restart deployment/airbnb-api -n airbnb-clone

# Wait for restart
kubectl rollout status deployment/airbnb-api -n airbnb-clone
```

---

## ⚙️ Configuration

### Kubernetes Resources

#### Namespace
Isolates your application from system services:
```bash
kubectl get namespace airbnb-clone
```

#### Secrets
Stores sensitive data (database credentials, API keys):
```bash
kubectl get secret airbnb-secrets -n airbnb-clone
kubectl describe secret airbnb-secrets -n airbnb-clone
```

#### ConfigMap
Stores non-sensitive configuration:
```bash
kubectl get configmap airbnb-config -n airbnb-clone
kubectl describe configmap airbnb-config -n airbnb-clone
```

#### Deployments
Manages pod replicas:
```bash
kubectl get deployment -n airbnb-clone
kubectl describe deployment airbnb-api -n airbnb-clone
```

#### Services
Exposes pods to network:
```bash
kubectl get svc -n airbnb-clone
kubectl describe svc airbnb-client-service -n airbnb-clone
```

### Environment Variables

Set in Kubernetes secrets and configmap:

**Database Connection:**
- `DB_URL`: Cosmos DB connection string

**Authentication:**
- `JWT_SECRET`: JWT signing secret
- `SESSION_SECRET`: Session encryption secret

**External Services:**
- `CLOUDINARY_NAME`: Cloudinary account name
- `CLOUDINARY_API_KEY`: Cloudinary API key
- `CLOUDINARY_API_SECRET`: Cloudinary API secret

**Application:**
- `PORT`: API port (4000)
- `JWT_EXPIRY`: JWT token expiry (20d)
- `COOKIE_TIME`: Cookie expiry in days (7)
- `CLIENT_URL`: Frontend URL

---

## 🛠️ Management & Operations

### Monitoring

```bash
# Pod status
kubectl get pods -n airbnb-clone

# Pod resource usage
kubectl top pods -n airbnb-clone

# Node resource usage
kubectl top nodes

# Pod events
kubectl get events -n airbnb-clone

# Detailed pod info
kubectl describe pod <pod-name> -n airbnb-clone
```

### Logging

```bash
# View logs (last 100 lines)
kubectl logs -n airbnb-clone deployment/airbnb-api --tail=100

# Follow logs in real-time
kubectl logs -n airbnb-clone deployment/airbnb-api -f

# Logs from specific pod
kubectl logs <pod-name> -n airbnb-clone

# Previous logs (if pod crashed)
kubectl logs <pod-name> -n airbnb-clone --previous
```

### Scaling

#### Scale Pods
```bash
# Scale API to 3 replicas
kubectl scale deployment airbnb-api -n airbnb-clone --replicas=3

# Scale client to 3 replicas
kubectl scale deployment airbnb-client -n airbnb-clone --replicas=3

# Check status
kubectl get deployment -n airbnb-clone
```

#### Scale Cluster Nodes
```bash
# Scale AKS to 3 nodes
az aks scale \
  --name $AKS_CLUSTER \
  --resource-group $RESOURCE_GROUP \
  --node-count 3

# Check nodes
kubectl get nodes
```

### Rolling Updates

```bash
# Update image
kubectl set image deployment/airbnb-api \
  api=$ACR_SERVER/airbnb-api:v2 \
  -n airbnb-clone

# Check rollout status
kubectl rollout status deployment/airbnb-api -n airbnb-clone

# Rollback if needed
kubectl rollout undo deployment/airbnb-api -n airbnb-clone
```

### Restart Services

```bash
# Restart API
kubectl rollout restart deployment/airbnb-api -n airbnb-clone

# Restart Client
kubectl rollout restart deployment/airbnb-client -n airbnb-clone

# Wait for restart
kubectl rollout status deployment/airbnb-api -n airbnb-clone
```

---

## 🐛 Troubleshooting

### Pods Stuck in ImagePullBackOff

**Problem:** Cannot pull image from ACR

**Solution:**
```bash
# Verify ACR access
az aks update \
  --name $AKS_CLUSTER \
  --resource-group $RESOURCE_GROUP \
  --attach-acr $ACR_NAME

# Check pod status
kubectl describe pod <pod-name> -n airbnb-clone

# Check image exists in ACR
az acr repository show-tags --name $ACR_NAME --repository airbnb-api
```

### Pods Stuck in CrashLoopBackOff

**Problem:** Application crashes on startup

**Solution:**
```bash
# Check logs
kubectl logs <pod-name> -n airbnb-clone

# Common issues:
# - Database connection failed: Check DB_URL in secrets
# - Port already in use: Check PORT configuration
# - Missing environment variables: Verify secrets/configmap

# Debug with shell access
kubectl exec -it <pod-name> -n airbnb-clone -- /bin/sh
```

### LoadBalancer Stuck in Pending

**Problem:** External IP not assigned

**Solution:**
```bash
# Wait 5-10 minutes for Azure provisioning
kubectl get svc -n airbnb-clone -w

# Check service events
kubectl describe svc airbnb-client-service -n airbnb-clone

# Check Azure quota
az vm list-usage --location westeurope --output table
```

### Cannot Connect to Database

**Problem:** Database connection errors in logs

**Solution:**
```bash
# Verify connection string in secrets
kubectl get secret airbnb-secrets -n airbnb-clone -o yaml

# Check Cosmos DB firewall
# Azure Portal → Cosmos DB → Firewall → Allow Azure services

# Test connection string format
# mongodb+srv://<user>:<password>@<endpoint>.mongodb.net/<database>?...
```

### Application Returns 502/503 Error

**Problem:** API unavailable

**Solution:**
```bash
# Check pod status
kubectl get pods -n airbnb-clone

# Check logs for errors
kubectl logs -n airbnb-clone deployment/airbnb-api -f

# Restart deployment
kubectl rollout restart deployment/airbnb-api -n airbnb-clone

# Check resource limits
kubectl top pods -n airbnb-clone
```

### Terraform Apply Fails

**Problem:** Resource creation fails

**Solutions:**
```bash
# Check quotas
az vm list-usage --location westeurope --output table

# Verify resource names are unique (ACR, Cosmos DB)
# Change names in terraform/main.tf if needed

# Try again
terraform apply tfplan

# If stuck, destroy and restart
terraform destroy
terraform apply
```

---

## 🔄 CI/CD Pipeline

### GitHub Actions Setup

#### 1. Create Azure Service Principal

```bash
# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Create service principal
az ad sp create-for-rbac \
  --name "airbnb-clone-github" \
  --role contributor \
  --scopes /subscriptions/$SUBSCRIPTION_ID \
  --sdk-auth
```

**Save the JSON output** - you'll need it for GitHub secrets.

#### 2. Add GitHub Secret

1. Go to GitHub repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `AZURE_CREDENTIALS`
4. Value: Paste the JSON from step 1
5. Save

#### 3. Update Workflow

Edit `.github/workflows/ci-cd.yml`:

```yaml
env:
  AZURE_RESOURCE_GROUP: airbnb-clone-rg
  AKS_CLUSTER_NAME: airbnb-clone-aks
  ACR_NAME: airbnbcloneacr
```

Update with your actual values.

#### 4. Trigger Pipeline

```bash
# Make a code change
echo "# CI/CD Test" >> README.md

# Commit and push
git add .
git commit -m "Trigger CI/CD"
git push origin main
```

**Watch the pipeline:**
Go to GitHub → Actions → See deployment in progress

### Pipeline Stages

1. **Build & Test**
   - Install dependencies
   - Run tests (if available)

2. **Build Docker Images**
   - Build API image
   - Build Client image
   - Push to ACR

3. **Deploy to AKS**
   - Update manifests
   - Deploy to Kubernetes
   - Verify deployment

---

## 💰 Cost Management

### Estimate Monthly Costs (24/7 running)

| Service | Configuration | Cost/Month |
|---------|--------------|-----------|
| AKS Compute | 2 x B2s nodes | ~$60 |
| Cosmos DB | 400 RU/s | ~$25 |
| Container Registry | Standard | ~$20 |
| Load Balancer | Standard | ~$20 |
| Networking | Data transfer | ~$10 |
| **Total** | | **~$135** |

### Cost Optimization

```bash
# Stop AKS cluster (save ~$40/month)
az aks stop \
  --name $AKS_CLUSTER \
  --resource-group $RESOURCE_GROUP

# Start when needed
az aks start \
  --name $AKS_CLUSTER \
  --resource-group $RESOURCE_GROUP
```

---

## 🧹 Cleanup

### Stop Resources (Keep Infrastructure)

```bash
# Stop AKS cluster
az aks stop \
  --name $AKS_CLUSTER \
  --resource-group $RESOURCE_GROUP
```

### Delete Everything

```bash
cd terraform

# Destroy all resources
terraform destroy

# Confirm when prompted
```

---

## 📊 Useful Commands Reference

### Kubernetes

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes
kubectl get all -n airbnb-clone

# Pods
kubectl get pods -n airbnb-clone
kubectl describe pod <pod-name> -n airbnb-clone
kubectl logs <pod-name> -n airbnb-clone

# Services
kubectl get svc -n airbnb-clone
kubectl port-forward svc/<service-name> <local-port>:<remote-port> -n airbnb-clone

# Exec into pod
kubectl exec -it <pod-name> -n airbnb-clone -- /bin/bash
```

### Azure

```bash
# Resource groups
az group list --output table

# AKS
az aks get-credentials --resource-group <rg> --name <aks>
az aks stop --name <aks> --resource-group <rg>
az aks start --name <aks> --resource-group <rg>

# Container Registry
az acr login --name <acr-name>
az acr repository list --name <acr-name>
az acr repository show-tags --name <acr-name> --repository <repo>

# Cosmos DB
az cosmosdb list --resource-group <rg>
```

### Docker

```bash
# Build image
docker build -t <image-name> .

# Tag image
docker tag <image-name> <registry>/<image-name>:latest

# Push image
docker push <registry>/<image-name>:latest

# View images
docker images
```

---

## 📚 Additional Resources

- [Azure AKS Documentation](https://docs.microsoft.com/azure/aks/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Azure Cosmos DB](https://docs.microsoft.com/azure/cosmos-db/)
- [GitHub Actions](https://docs.github.com/actions)

---

## 🎓 Key Concepts

### Why Kubernetes (AKS)?
- Container orchestration
- Auto-scaling and self-healing
- Industry standard
- Multi-cloud compatible

### Why Cosmos DB?
- Fully managed service (no server maintenance)
- 99.99% SLA
- MongoDB compatible API
- Automatic backups and global distribution

### Why Infrastructure as Code?
- Reproducible environments
- Version controlled
- Documentation as code
- Quick disaster recovery

---

## 📝 For Local Development

For local development setup, see [README.md](README.md) in the root of this directory.

---

## 🎯 Next Steps

1. ✅ Read this entire document
2. ✅ Install prerequisites
3. ✅ Run `./deploy.sh` or follow step-by-step guide
4. ✅ Test application in browser
5. ✅ Setup CI/CD pipeline (optional)
6. ✅ Monitor and manage deployment

---

**Questions?** Refer to the Troubleshooting section or check the parent project documentation.

**Good luck with your cloud deployment! 🚀**
