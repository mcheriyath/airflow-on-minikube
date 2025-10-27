# 🚁 Airflow 3.0.2 on Minikube

This repository contains scripts to deploy Apache Airflow 3.0.2 on a local Minikube cluster. Perfect for local development and testing! ✨

## 📋 Prerequisites

Before running the scripts, ensure you have the following tools installed:

- **Docker**: Container runtime
- **Minikube**: Local Kubernetes cluster
- **kubectl**: Kubernetes command-line tool
- **Helm**: Kubernetes package manager
- **Python 3.x**: For generating Fernet keys (optional)

### 🔧 Installation Commands (Ubuntu/Debian)

```bash
# Install Docker
sudo apt update
sudo apt install -y docker.io
sudo usermod -aG docker $USER

# Install Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## 🚀 Quick Start

### 1. Deploy Airflow

Run the smart deployment script:

```bash
./deploy-airflow-smart.sh
```

The script will:
- ✅ Check if required images exist locally
- ✅ Deploy PostgreSQL with official postgres:15 image
- ✅ Verify PostgreSQL connectivity
- ✅ Deploy Airflow 3.0.2 with optimized configuration
- ✅ Monitor pod health with dynamic timeouts
- ✅ Provide detailed status updates

### 2. Access Airflow

Port-forward to access the Airflow UI:

```bash
kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow
```

Then open http://localhost:8080

**Login Credentials:**
- Username: `admin`
- Password: `admin`

## 🛠️ Management Commands

### Check Status
```bash
kubectl get pods -n airflow
kubectl get svc -n airflow
```

### View Logs
```bash
# Scheduler logs
kubectl logs -n airflow -l component=scheduler --tail=50 -f

# API Server logs  
kubectl logs -n airflow -l component=api-server --tail=50 -f

# PostgreSQL logs
kubectl logs -n airflow -l app=postgresql --tail=50 -f
```

### Clean Up
```bash
helm uninstall airflow -n airflow
kubectl delete namespace airflow
```

## 📦 Configuration

The deployment includes:

### ⚙️ Components
- **Executor**: CeleryExecutor for distributed processing
- **Database**: PostgreSQL 
## 🔧 What's Deployed

### Components
- **Airflow Version**: 3.0.2 (latest available in Helm chart 1.18.0)
- **Executor**: KubernetesExecutor (no Redis required)
- **Database**: PostgreSQL 15 (official image)
- **API Server**: Serves UI and API (replaces webserver in Airflow 3.x)
- **Scheduler**: DAG scheduling and execution
- **Triggerer**: For deferred/async tasks
- **DAG Processor**: Processes DAG files
- **StatsD**: Metrics collection

### 🔧 Features
- Persistent storage for DAGs and logs
- Example DAGs enabled
- RBAC authentication
- Resource limits configured for stability
- All pods on control-plane node (avoids sandbox issues)

### 📊 Resource Allocation
```
Component       CPU Request  Memory Request  CPU Limit  Memory Limit
Webserver       500m        512Mi          1000m      1Gi
Scheduler       500m        512Mi          1000m      1Gi
PostgreSQL      250m        256Mi          500m       512Mi
```

## 📝 Example DAG

An example DAG (`example_dag.py`) is included to test the deployment:

```python
# Features demonstrated:
- PythonOperator for custom Python functions
- BashOperator for shell commands  
- Task dependencies
- Proper DAG configuration
```

To add this DAG to your deployment:

1. Copy the DAG to the Airflow DAGs volume:
```bash
kubectl cp example_dag.py airflow/$(kubectl get pods -n airflow -l component=scheduler -o jsonpath='{.items[0].metadata.name}'):/opt/airflow/dags/
```

2. Or use the web UI to upload it directly

## 🔍 Troubleshooting

### Common Issues

**Pods not starting:**
```bash
# Check pod status and events
kubectl get pods -n airflow
kubectl describe pod <pod-name> -n airflow
kubectl get events -n airflow --sort-by='.lastTimestamp'
```

**Database connection issues:**
```bash
# Test PostgreSQL connectivity
kubectl exec -n airflow $(kubectl get pod -n airflow -l app=postgresql -o jsonpath='{.items[0].metadata.name}') -- psql -U airflow -d airflow -c "SELECT 1;"

# Check PostgreSQL logs
kubectl logs -n airflow -l app=postgresql --tail=50
```

**Port forward already in use:**
```bash
# Kill existing port-forward
pkill -f "port-forward.*8080"
```

### Known Issues & Solutions

**Issue: Bitnami PostgreSQL Image Not Found**  
Solution: Using official `postgres:15` image instead

**Issue: Pod Sandbox Changes Causing CrashLoopBackOff**  
Solution: All pods scheduled on control-plane node (minikube)

**Issue: Airflow 3.1.0 Not Available**  
Solution: Using 3.0.2 (latest in Helm chart 1.18.0)

**Issue: No Webserver Component**  
Note: Airflow 3.x replaced webserver with API Server

## 📈 Scaling and Performance

### Scale Workers
```bash
# Scale to 5 workers
./manage-airflow.sh scale 5

# Or use kubectl directly  
kubectl scale deployment airflow-worker --replicas=5 -n airflow
```

### Monitor Resource Usage
```bash
# Check resource usage
kubectl top pods -n airflow
kubectl top nodes
```

### Increase Minikube Resources
```bash
minikube stop
minikube start --memory=12288 --cpus=8 --disk-size=40g
```

## 🔒 Security Notes

- Default credentials are `admin/admin` - change in production
- Fernet keys are auto-generated and stored as Kubernetes secrets
- RBAC is enabled for proper access control
- PostgreSQL uses dedicated airflow user with limited permissions

## 🧹 Cleanup

To completely remove Airflow and free up resources:

```bash
# Option 1: Use management script
./manage-airflow.sh uninstall

# Option 2: Manual cleanup
helm uninstall airflow -n airflow
kubectl delete namespace airflow
kubectl delete pv $(kubectl get pv -o name | grep airflow)
```

To stop Minikube:
```bash
minikube stop
# Or to delete completely
minikube delete
```

## 🎯 What's Next?

1. **Add Custom DAGs**: Copy Python files to DAG persistence volume
2. **Configure Connections**: Use Airflow UI to add connections
3. **Monitor**: Check scheduler/triggerer logs for DAG execution
4. **Scale**: Adjust resources in Helm values if needed

## 📚 Resources

- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [Airflow Helm Chart](https://airflow.apache.org/docs/helm-chart/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

---

**Happy DAG building!** 🎉

*Deployed by: Mithun Cheriyath (@mcheriyath)*  
*Date: October 27, 2025*  
*Location: Atlanta, Georgia 🍑*
 