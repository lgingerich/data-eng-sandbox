#!/bin/bash

# Check if Minikube is installed
if ! command -v minikube &> /dev/null; then
    echo "Minikube is not installed. Please install Minikube first."
    exit 1
fi

# Start Minikube if it's not running
if ! minikube status | grep -q "Running"; then
    echo "Starting Minikube..."
    minikube start
fi

# Enable ingress addon for Minikube
minikube addons enable ingress

# Install Helm (if not already installed)
if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
fi

# Add the official Apache Airflow Helm chart repository
helm repo add apache-airflow https://airflow.apache.org
helm repo update

# Create a namespace for Airflow
kubectl create namespace airflow

# Install Airflow using Helm
helm install airflow apache-airflow/airflow \
    --namespace airflow \
    --set executor=LocalExecutor \
    --set webserver.defaultUser.enabled=true \
    --set webserver.defaultUser.username=admin \
    --set webserver.defaultUser.password=admin \
    --set webserver.defaultUser.email=admin@example.com \
    --set ingress.enabled=true \
    --set ingress.hosts[0]=airflow.local

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod --all -n airflow --timeout=300s

# Get Minikube IP
MINIKUBE_IP=$(minikube ip)

echo "Airflow installation complete!"
echo "Add the following line to your /etc/hosts file:"
echo "$MINIKUBE_IP airflow.local"
echo "Then access Airflow UI at: http://airflow.local"