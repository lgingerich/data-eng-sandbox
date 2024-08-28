#!/bin/bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Error logging function
error_log() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

# Warning logging function
warning_log() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check and install Homebrew
install_homebrew() {
    if ! command_exists brew; then
        log "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [ $? -ne 0 ]; then
            error_log "Failed to install Homebrew. Exiting."
            exit 1
        fi
    else
        log "Homebrew is already installed."
    fi
}

# Function to install or upgrade a Homebrew package
install_or_upgrade_package() {
    if brew list "$1" &>/dev/null; then
        log "Upgrading $1..."
        brew upgrade "$1" || warning_log "Failed to upgrade $1. Continuing..."
    else
        log "Installing $1..."
        brew install "$1" || { error_log "Failed to install $1. Exiting."; exit 1; }
    fi
}

# Function to check and install dependencies
install_dependencies() {
    log "Checking and installing dependencies..."
    
    install_homebrew

    # Install or upgrade required packages
    install_or_upgrade_package "kubectl"
    install_or_upgrade_package "helm"
    install_or_upgrade_package "docker"

    # Check Docker daemon
    if ! docker info &>/dev/null; then
        warning_log "Docker daemon is not running. Please start Docker and run this script again."
        exit 1
    fi

    log "All dependencies are installed and up to date."
}

# Function to check if a port is available
is_port_available() {
    ! nc -z localhost $1 &>/dev/null
}

# Function to find an available port
find_available_port() {
    local port=$1
    while ! is_port_available $port; do
        port=$((port + 1))
    done
    echo $port
}

# Function to setup Airflow
setup_airflow() {
    log "Setting up Airflow..."

    # Add Airflow Helm repository
    helm repo add apache-airflow https://airflow.apache.org || { error_log "Failed to add Airflow Helm repo. Exiting."; exit 1; }
    helm repo update || { error_log "Failed to update Helm repos. Exiting."; exit 1; }

    # Check if the namespace exists, if not create it
    if ! kubectl get namespace airflow &>/dev/null; then
        kubectl create namespace airflow || { error_log "Failed to create airflow namespace. Exiting."; exit 1; }
    fi

    # Install Airflow using Helm
    helm install airflow apache-airflow/airflow \
        --namespace airflow \
        --set executor=CeleryExecutor \
        --set webserver.defaultUser.enabled=true \
        --set webserver.defaultUser.username=admin \
        --set webserver.defaultUser.password=admin \
        --set webserver.defaultUser.email=admin@example.com \
        --set webserver.defaultUser.firstName=admin \
        --set webserver.defaultUser.lastName=user \
        --set flower.enabled=false \
        || { error_log "Failed to install Airflow. Exiting."; exit 1; }

    # Wait for Airflow to be ready
    log "Waiting for Airflow pods to be ready..."
    kubectl wait --for=condition=ready pod -l component=webserver --timeout=300s -n airflow || { error_log "Airflow pods are not ready. Exiting."; exit 1; }

    log "Airflow setup completed successfully."
    log "You can access the Airflow webserver by running the 'run' command."
}

# Function to port-forward Airflow services
port_forward_services() {
    log "Setting up port forwarding..."

    # Find available port for webserver
    local webserver_port=$(find_available_port 8080)
    
    # Port forward Airflow webserver
    kubectl port-forward svc/airflow-webserver $webserver_port:8080 -n airflow &
    local webserver_pid=$!
    
    # Save webserver PID for later cleanup
    echo $webserver_pid > /tmp/airflow_webserver_pid

    log "Airflow webserver is accessible at http://localhost:$webserver_port"
    log "Default username: admin"
    log "Default password: admin"
}

# Setup function
setup() {
    log "Starting Airflow setup..."
    install_dependencies
    setup_airflow
    port_forward_services
    log "Airflow setup completed successfully."
}

# Run function
run() {
    log "Starting Airflow..."

    # Check if Airflow is already installed
    if ! helm list -n airflow | grep -q "airflow"; then
        error_log "Airflow is not installed. Please run the setup function first."
        exit 1
    fi

    # Check if deployments are scaled down, and scale them up if necessary
    local deployments=$(kubectl get deployments -n airflow -o name)
    for deployment in $deployments; do
        replicas=$(kubectl get $deployment -n airflow -o jsonpath='{.spec.replicas}')
        if [ "$replicas" -eq 0 ]; then
            log "Scaling up $deployment..."
            kubectl scale $deployment -n airflow --replicas=1
        fi
    done

    # Wait for pods to be ready
    log "Waiting for Airflow pods to be ready..."
    kubectl wait --for=condition=ready pod -l component=webserver --timeout=300s -n airflow || { error_log "Airflow pods are not ready. Exiting."; exit 1; }

    port_forward_services
    log "Airflow is now running and accessible."
}

# Shutdown function
shutdown() {
    log "Shutting down Airflow..."

    # Stop port forwarding
    if [ -f /tmp/airflow_webserver_pid ]; then
        kill $(cat /tmp/airflow_webserver_pid) 2>/dev/null || true
        rm /tmp/airflow_webserver_pid
    fi

    log "Airflow port-forwarding has been stopped."
}

# Teardown function
teardown() {
    log "Tearing down Airflow..."

    # First, perform a shutdown
    shutdown

    # Uninstall Airflow Helm release
    helm uninstall airflow -n airflow || { error_log "Failed to uninstall Airflow Helm release. Continuing..."; }

    # Delete the namespace
    kubectl delete namespace airflow || { error_log "Failed to delete airflow namespace. Continuing..."; }

    # Remove any leftover PVCs
    kubectl get pvc -n airflow -o name | xargs -r kubectl delete -n airflow || { error_log "Failed to delete PVCs. Continuing..."; }

    # Remove any leftover configmaps
    kubectl get configmap -n airflow -o name | xargs -r kubectl delete -n airflow || { error_log "Failed to delete ConfigMaps. Continuing..."; }

    log "Airflow has been completely torn down."
}

# Main execution
case "$1" in
    setup)
        setup
        ;;
    run)
        run
        ;;
    shutdown)
        shutdown
        ;;
    teardown)
        teardown
        ;;
    *)
        echo "Usage: $0 {setup|run|shutdown|teardown}"
        exit 1
        ;;
esac