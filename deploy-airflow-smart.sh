#!/bin/bash
# Smart Airflow 3.1.0 Deployment Script
# Features: Dynamic waits, health checks, early failure detection

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
MAX_WAIT_POSTGRES=300  # 5 minutes max for PostgreSQL
MAX_WAIT_AIRFLOW=600   # 10 minutes max for Airflow
CHECK_INTERVAL=10      # Check every 10 seconds

echo -e "${BLUE}🚁 Smart Airflow 3.0.2 Deployment for Minikube${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Function to check if image exists locally
check_image_exists() {
    local image=$1
    echo -e "${BLUE}🔍 Checking if image '$image' exists locally...${NC}"
    
    # Check on all minikube nodes
    for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
        if minikube ssh -n $node "docker images --format '{{.Repository}}:{{.Tag}}' | grep -q '^${image}$'" 2>/dev/null; then
            echo -e "${GREEN}✅ Image found on node: $node${NC}"
            return 0
        fi
    done
    
    echo -e "${YELLOW}⚠️  Image not found locally, will need to pull${NC}"
    return 1
}

# Function to wait for pods with smart checks
wait_for_pods() {
    local label=$1
    local namespace=$2
    local max_wait=$3
    local description=$4
    
    echo -e "${BLUE}⏳ Waiting for $description...${NC}"
    
    local elapsed=0
    local last_status=""
    
    while [ $elapsed -lt $max_wait ]; do
        # Get pod status
        local pod_info=$(kubectl get pods -n $namespace -l $label -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null || echo "")
        
        if [ -z "$pod_info" ]; then
            echo -e "${YELLOW}⏳ [$elapsed/${max_wait}s] No pods found yet, waiting...${NC}"
            sleep $CHECK_INTERVAL
            elapsed=$((elapsed + CHECK_INTERVAL))
            continue
        fi
        
        # Parse pod info
        local pod_name=$(echo "$pod_info" | awk '{print $1}')
        local phase=$(echo "$pod_info" | awk '{print $2}')
        local restarts=$(echo "$pod_info" | awk '{print $3}')
        
        # Check for Running state
        if [ "$phase" == "Running" ]; then
            # Check if container is actually ready
            local ready=$(kubectl get pod $pod_name -n $namespace -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
            if [ "$ready" == "true" ]; then
                echo -e "${GREEN}✅ $description is ready! (${elapsed}s)${NC}"
                return 0
            fi
        fi
        
        # Check for CrashLoopBackOff or high restart count
        if [ ! -z "$restarts" ] && [ "$restarts" -gt 3 ]; then
            echo -e "${RED}❌ Pod $pod_name is restarting frequently (restarts: $restarts)${NC}"
            echo -e "${RED}Recent logs:${NC}"
            kubectl logs $pod_name -n $namespace --tail=20 2>/dev/null || echo "Could not retrieve logs"
            
            echo -e "${RED}Pod events:${NC}"
            kubectl describe pod $pod_name -n $namespace | grep -A 10 "Events:" || true
            
            return 1
        fi
        
        # Status update (only if changed)
        local current_status="Phase: $phase, Restarts: ${restarts:-0}"
        if [ "$current_status" != "$last_status" ]; then
            echo -e "${YELLOW}⏳ [$elapsed/${max_wait}s] $pod_name - $current_status${NC}"
            last_status=$current_status
        fi
        
        sleep $CHECK_INTERVAL
        elapsed=$((elapsed + CHECK_INTERVAL))
    done
    
    echo -e "${RED}❌ Timeout waiting for $description after ${max_wait}s${NC}"
    return 1
}

# Clean up existing installation
echo -e "${YELLOW}🧹 Cleaning up existing installation...${NC}"
helm uninstall airflow -n airflow 2>/dev/null || true
kubectl delete namespace airflow 2>/dev/null || true

echo "Waiting for namespace deletion..."
while kubectl get namespace airflow &>/dev/null; do
    sleep 2
done

# Create namespace
echo -e "${GREEN}📦 Creating namespace...${NC}"
kubectl create namespace airflow

# Check if PostgreSQL image exists
POSTGRES_IMAGE="postgres:15"
if check_image_exists "$POSTGRES_IMAGE"; then
    echo -e "${GREEN}Image exists, PostgreSQL startup should be fast${NC}"
else
    echo -e "${YELLOW}Image needs to be pulled, adding extra wait time${NC}"
    MAX_WAIT_POSTGRES=480  # 8 minutes if pulling image
fi

# Deploy PostgreSQL
echo -e "${GREEN}🐘 Deploying PostgreSQL...${NC}"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: airflow
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql
  namespace: airflow
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      nodeSelector:
        kubernetes.io/hostname: minikube
      containers:
      - name: postgresql
        image: postgres:15
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_USER
          value: "airflow"
        - name: POSTGRES_PASSWORD
          value: "airflow"
        - name: POSTGRES_DB
          value: "airflow"
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  namespace: airflow
spec:
  selector:
    app: postgresql
  ports:
  - port: 5432
    targetPort: 5432
EOF

# Wait for PostgreSQL with smart checks
if ! wait_for_pods "app=postgresql" "airflow" $MAX_WAIT_POSTGRES "PostgreSQL"; then
    echo -e "${RED}❌ PostgreSQL failed to start. Aborting.${NC}"
    exit 1
fi

# Additional verification - test database connection
echo -e "${BLUE}🔍 Verifying PostgreSQL connectivity...${NC}"
POD_NAME=$(kubectl get pod -n airflow -l app=postgresql -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n airflow $POD_NAME -- psql -U airflow -d airflow -c "SELECT 1;" &>/dev/null; then
    echo -e "${GREEN}✅ PostgreSQL is accepting connections${NC}"
else
    echo -e "${RED}❌ PostgreSQL is running but not accepting connections${NC}"
    kubectl logs $POD_NAME -n airflow --tail=30
    exit 1
fi

# Check if Airflow image exists
AIRFLOW_IMAGE="apache/airflow:3.0.2"
if check_image_exists "$AIRFLOW_IMAGE"; then
    echo -e "${GREEN}Airflow image exists, deployment should be faster${NC}"
else
    echo -e "${YELLOW}Airflow image needs to be pulled, adding extra wait time${NC}"
    MAX_WAIT_AIRFLOW=900  # 15 minutes if pulling
fi

# Deploy Airflow
echo -e "${GREEN}🚀 Deploying Airflow 3.0.2 (latest available)...${NC}"

cat > /tmp/airflow-values.yaml <<'EOF'
defaultAirflowTag: "3.0.2"
airflowVersion: "3.0.2"

env:
  - name: "AIRFLOW__CORE__LOAD_EXAMPLES"
    value: "True"

postgresql:
  enabled: false

data:
  metadataConnection:
    user: airflow
    pass: airflow
    protocol: postgresql
    host: postgresql
    port: 5432
    db: airflow
    sslmode: disable

executor: "KubernetesExecutor"

redis:
  enabled: false

webserver:
  defaultUser:
    enabled: true
    username: admin
    password: admin
    email: admin@example.com
    firstName: Admin
    lastName: User
    role: Admin
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

scheduler:
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

dags:
  persistence:
    enabled: true
    size: 1Gi

logs:
  persistence:
    enabled: true
    size: 1Gi

rbac:
  create: true

serviceAccount:
  create: true

# Force all pods to control plane to avoid sandbox issues
nodeSelector:
  kubernetes.io/hostname: minikube
EOF

helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --values /tmp/airflow-values.yaml \
  --timeout 3m \
  --wait-for-jobs=false

echo -e "${BLUE}📊 Monitoring Airflow deployment...${NC}"

# Monitor multiple Airflow components
declare -A components=(
    ["airflow-scheduler"]="Scheduler"
    ["airflow-webserver"]="Webserver"
    ["airflow-triggerer"]="Triggerer"
)

echo -e "${YELLOW}Waiting for Airflow components to initialize...${NC}"
sleep 15

all_ready=false
elapsed=0

while [ $elapsed -lt $MAX_WAIT_AIRFLOW ] && [ "$all_ready" = false ]; do
    all_ready=true
    
    for label in "${!components[@]}"; do
        description="${components[$label]}"
        
        pod_status=$(kubectl get pods -n airflow -l component=$label -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
        ready=$(kubectl get pods -n airflow -l component=$label -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        
        if [ "$pod_status" != "Running" ] || [ "$ready" != "true" ]; then
            all_ready=false
            echo -e "${YELLOW}⏳ [$elapsed/${MAX_WAIT_AIRFLOW}s] $description: $pod_status (ready: $ready)${NC}"
        else
            echo -e "${GREEN}✅ $description: Running${NC}"
        fi
    done
    
    if [ "$all_ready" = true ]; then
        break
    fi
    
    sleep $CHECK_INTERVAL
    elapsed=$((elapsed + CHECK_INTERVAL))
done

if [ "$all_ready" = true ]; then
    echo ""
    echo -e "${GREEN}✅ All Airflow components are ready!${NC}"
    echo ""
    echo -e "${BLUE}📍 Access Information:${NC}"
    echo ""
    echo -e "Run this command to access Airflow UI:"
    echo -e "${YELLOW}kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow${NC}"
    echo ""
    echo -e "Then open: ${YELLOW}http://localhost:8080${NC}"
    echo ""
    echo -e "${BLUE}🔐 Credentials:${NC}"
    echo -e "   Username: ${YELLOW}admin${NC}"
    echo -e "   Password: ${YELLOW}admin${NC}"
    echo ""
    echo -e "${GREEN}🎉 Airflow 3.0.2 is ready!${NC}"
    exit 0
else
    echo -e "${RED}❌ Timeout waiting for Airflow components${NC}"
    echo -e "${YELLOW}Current pod status:${NC}"
    kubectl get pods -n airflow
    echo ""
    echo -e "${YELLOW}Check logs with:${NC}"
    echo "kubectl logs -n airflow -l component=airflow-scheduler --tail=50"
    echo "kubectl logs -n airflow -l component=airflow-webserver --tail=50"
    exit 1
fi
