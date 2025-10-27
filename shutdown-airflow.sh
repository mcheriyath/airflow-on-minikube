#!/bin/bash
# Airflow Shutdown Script
# Safely shuts down Airflow deployment on Minikube

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}🛑 Shutting Down Airflow on Minikube${NC}"
echo -e "${RED}====================================${NC}"
echo ""

# Check if namespace exists
if ! kubectl get namespace airflow &>/dev/null; then
    echo -e "${YELLOW}⚠️  Airflow namespace not found. Nothing to shutdown.${NC}"
    exit 0
fi

echo -e "${BLUE}📊 Current Airflow resources:${NC}"
kubectl get all -n airflow
echo ""

# Ask for confirmation
read -p "$(echo -e ${YELLOW}Are you sure you want to shutdown Airflow? This will delete all data! [y/N]: ${NC})" -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}ℹ️  Shutdown cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}🔄 Starting shutdown process...${NC}"

# Step 1: Stop Helm release
echo -e "${BLUE}1️⃣  Removing Airflow Helm release...${NC}"
if helm list -n airflow | grep -q airflow; then
    helm uninstall airflow -n airflow
    echo -e "${GREEN}✅ Helm release removed${NC}"
else
    echo -e "${YELLOW}⚠️  No Helm release found${NC}"
fi

# Step 2: Wait for pods to terminate
echo -e "${BLUE}2️⃣  Waiting for pods to terminate...${NC}"
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    pod_count=$(kubectl get pods -n airflow --no-headers 2>/dev/null | wc -l)
    if [ "$pod_count" -eq 0 ]; then
        echo -e "${GREEN}✅ All pods terminated${NC}"
        break
    fi
    echo -e "${YELLOW}⏳ [$elapsed/${timeout}s] Waiting for $pod_count pods to terminate...${NC}"
    sleep 5
    elapsed=$((elapsed + 5))
done

# Step 3: Handle PostgreSQL deployment and data
echo -e "${BLUE}3️⃣  Stopping PostgreSQL (keeping data safe)...${NC}"

# Stop PostgreSQL deployment and service but preserve PVC
if kubectl get deployment postgresql -n airflow &>/dev/null; then
    kubectl delete deployment postgresql -n airflow
    echo -e "${GREEN}✅ PostgreSQL deployment stopped${NC}"
fi

if kubectl get service postgresql -n airflow &>/dev/null; then
    kubectl delete service postgresql -n airflow
    echo -e "${GREEN}✅ PostgreSQL service removed${NC}"
fi

# Check for persistent data and give options
pvc_count=$(kubectl get pvc -n airflow --no-headers 2>/dev/null | wc -l)
if [ "$pvc_count" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Found $pvc_count persistent volume claims:${NC}"
    kubectl get pvc -n airflow
    echo ""
    echo -e "${BLUE}Data Options:${NC}"
    echo -e "  ${GREEN}k${NC} - Keep data (recommended - preserve DAGs, logs, DB)"
    echo -e "  ${RED}d${NC} - Delete data (fresh start next time)"
    echo ""
    read -p "$(echo -e ${YELLOW}Keep or Delete persistent data? [K/d]: ${NC})" -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Dd]$ ]]; then
        kubectl delete pvc --all -n airflow
        echo -e "${RED}✅ Persistent data deleted - next deployment will be fresh${NC}"
        DATA_PRESERVED=false
    else
        echo -e "${GREEN}✅ Persistent data preserved - next deployment will reuse existing data${NC}"
        DATA_PRESERVED=true
    fi
else
    DATA_PRESERVED=false
fi

# Step 4: Delete namespace
echo -e "${BLUE}4️⃣  Removing namespace...${NC}"
kubectl delete namespace airflow

# Wait for namespace deletion
echo -e "${BLUE}⏳ Waiting for namespace deletion...${NC}"
while kubectl get namespace airflow &>/dev/null; do
    sleep 2
done

echo ""
echo -e "${GREEN}✅ Airflow shutdown complete!${NC}"
echo ""
echo -e "${BLUE}📝 What was removed:${NC}"
echo "   • All Airflow components (webserver, scheduler, triggerer)"
echo "   • PostgreSQL database pod and service"
echo "   • Kubernetes resources (deployments, services, etc.)"
echo "   • Airflow namespace"

if [ "$DATA_PRESERVED" = true ]; then
    echo -e "   ${GREEN}• Persistent data PRESERVED (DAGs, logs, database)${NC}"
    echo ""
    echo -e "${GREEN}💾 Data Status: Your data is safe!${NC}"
    echo -e "   Next deployment will reuse existing DAGs, connections, and task history."
else
    echo -e "   ${RED}• Persistent data DELETED (fresh start)${NC}"
    echo ""
    echo -e "${BLUE}🆕 Next deployment will be a fresh installation.${NC}"
fi
echo ""
echo -e "${BLUE}🔄 To redeploy Airflow, run: ${YELLOW}./deploy-airflow-smart.sh${NC}"