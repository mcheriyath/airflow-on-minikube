#!/bin/bash

# 🔍 Pre-flight Check Script for Airflow Deployment
# Verifies all prerequisites are met before deployment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if command exists
check_command() {
    if command -v "$1" &> /dev/null; then
        local version=$($1 --version 2>/dev/null | head -1)
        print_success "$1 is installed - $version"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

# Check Docker
check_docker() {
    print_header "🐳 Checking Docker..."
    
    if check_command "docker"; then
        if docker info &>/dev/null; then
            print_success "Docker daemon is running"
        else
            print_error "Docker daemon is not running or accessible"
            echo "   Try: sudo systemctl start docker"
            echo "   Or add user to docker group: sudo usermod -aG docker \$USER"
            return 1
        fi
    else
        print_error "Docker is required but not installed"
        echo "   Install with: sudo apt install -y docker.io"
        return 1
    fi
}

# Check Minikube
check_minikube() {
    print_header "☸️  Checking Minikube..."
    
    if check_command "minikube"; then
        local status=$(minikube status --format='{{.Host}}' 2>/dev/null || echo "Stopped")
        if [[ "$status" == "Running" ]]; then
            print_success "Minikube is running"
            local ip=$(minikube ip 2>/dev/null)
            echo "   Cluster IP: $ip"
        else
            print_warning "Minikube is installed but not running"
            echo "   Start with: minikube start"
        fi
    else
        print_error "Minikube is required but not installed"
        echo "   Install from: https://minikube.sigs.k8s.io/docs/start/"
        return 1
    fi
}

# Check kubectl
check_kubectl() {
    print_header "🎛️  Checking kubectl..."
    
    if check_command "kubectl"; then
        if kubectl cluster-info &>/dev/null; then
            print_success "kubectl can connect to cluster"
            local context=$(kubectl config current-context 2>/dev/null)
            echo "   Current context: $context"
        else
            print_warning "kubectl is installed but cannot connect to cluster"
        fi
    else
        print_error "kubectl is required but not installed"
        echo "   Install from: https://kubernetes.io/docs/tasks/tools/"
        return 1
    fi
}

# Check Helm
check_helm() {
    print_header "⚓ Checking Helm..."
    
    if check_command "helm"; then
        local repos=$(helm repo list 2>/dev/null | wc -l)
        print_success "Helm has $((repos-1)) repositories configured"
    else
        print_error "Helm is required but not installed"  
        echo "   Install with: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
        return 1
    fi
}

# Check Python (optional)
check_python() {
    print_header "🐍 Checking Python (for Fernet key generation)..."
    
    if check_command "python3"; then
        # Check if cryptography is available
        if python3 -c "from cryptography.fernet import Fernet" 2>/dev/null; then
            print_success "Python cryptography library is available"
        else
            print_warning "Python cryptography library not found"
            echo "   Install with: pip3 install cryptography"
            echo "   (OpenSSL will be used as fallback)"
        fi
    elif check_command "python"; then
        if python -c "from cryptography.fernet import Fernet" 2>/dev/null; then
            print_success "Python cryptography library is available"
        else
            print_warning "Python cryptography library not found"
        fi
    else
        print_warning "Python not found - will use OpenSSL for Fernet key generation"
    fi
}

# Check system resources
check_resources() {
    print_header "💾 Checking System Resources..."
    
    # Check available memory
    local total_mem=$(free -g | awk 'NR==2{printf "%.1f", $2}')
    local available_mem=$(free -g | awk 'NR==2{printf "%.1f", $7}')
    
    if (( $(echo "$available_mem >= 4" | bc -l) )); then
        print_success "Available memory: ${available_mem}GB (recommended: 4GB+)"
    else
        print_warning "Available memory: ${available_mem}GB (recommended: 4GB+)"
        echo "   Consider closing other applications"
    fi
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    if (( cpu_cores >= 2 )); then
        print_success "CPU cores: $cpu_cores (recommended: 2+)"
    else
        print_warning "CPU cores: $cpu_cores (recommended: 2+)"
    fi
    
    # Check disk space
    local disk_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if (( disk_space >= 10 )); then
        print_success "Available disk space: ${disk_space}GB (recommended: 10GB+)"
    else
        print_warning "Available disk space: ${disk_space}GB (recommended: 10GB+)"
    fi
}

# Check network connectivity
check_network() {
    print_header "🌐 Checking Network Connectivity..."
    
    if ping -c 1 8.8.8.8 &>/dev/null; then
        print_success "Internet connectivity is available"
    else
        print_error "No internet connectivity - required for downloading Helm charts"
        return 1
    fi
    
    # Check if we can reach Helm repository
    if curl -s --max-time 5 https://airflow.apache.org &>/dev/null; then
        print_success "Airflow Helm repository is reachable"
    else
        print_warning "Cannot reach Airflow Helm repository"
        echo "   Check firewall/proxy settings"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🔍 Airflow 3.1.0 Deployment Prerequisites Check${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo ""
    
    local failed_checks=0
    
    check_docker || ((failed_checks++))
    echo ""
    
    check_minikube || ((failed_checks++)) 
    echo ""
    
    check_kubectl || ((failed_checks++))
    echo ""
    
    check_helm || ((failed_checks++))
    echo ""
    
    check_python
    echo ""
    
    check_resources
    echo ""
    
    check_network || ((failed_checks++))
    echo ""
    
    # Summary
    if (( failed_checks == 0 )); then
        print_success "🎉 All prerequisites are met! Ready to deploy Airflow 3.1.0"
        echo ""
        echo -e "${GREEN}Next steps:${NC}"
        echo -e "   1. Run: ${YELLOW}./launch-airflow.sh${NC}"
        echo -e "   2. Wait for deployment to complete"
        echo -e "   3. Access Airflow at the provided URL"
    else
        print_error "❌ $failed_checks prerequisite check(s) failed"
        echo ""
        echo -e "${RED}Please fix the issues above before running the deployment script${NC}"
        exit 1
    fi
}

main "$@"