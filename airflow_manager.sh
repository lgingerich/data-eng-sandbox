#!/bin/bash

set -e

NAMESPACE="airflow"
RELEASE_NAME="airflow"

function check_dependencies() {
    echo "Checking dependencies..."
    command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl is required but not installed. Aborting."; exit 1; }
    command -v helm >/dev/null 2>&1 || { echo >&2 "helm is required but not installed. Aborting."; exit 1; }
}

function setup_airflow() {
    echo "Setting up Airflow locally..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Add Airflow Helm repo
    helm repo add apache-airflow https://airflow.apache.org
    helm repo update
    
    # Install Airflow
    helm install $RELEASE_NAME apache-airflow/airflow \
        --namespace $NAMESPACE \
        --set executor=LocalExecutor \
        --set webserver.defaultUser.enabled=true \
        --set webserver.defaultUser.username=admin \
        --set webserver.defaultUser.password=admin \
        --set webserver.defaultUser.email=admin@example.com

    echo "Waiting for Airflow pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=airflow --timeout=300s -n $NAMESPACE

    echo "Airflow is now set up! To access the Airflow UI, run:"
    echo "kubectl port-forward svc/$RELEASE_NAME-webserver 8080:8080 -n $NAMESPACE"
    echo "Then open http://localhost:8080 in your browser"
}

function teardown_airflow() {
    echo "Tearing down Airflow..."
    
    # Uninstall Airflow
    helm uninstall $RELEASE_NAME -n $NAMESPACE
    
    # Delete namespace
    kubectl delete namespace $NAMESPACE

    echo "Airflow has been torn down successfully."
}

function show_usage() {
    echo "Usage: $0 [setup|teardown]"
    exit 1
}

# Main script logic
if [ $# -eq 0 ]; then
    show_usage
fi

check_dependencies

case "$1" in
    setup)
        setup_airflow
        ;;
    teardown)
        teardown_airflow
        ;;
    *)
        show_usage
        ;;
esac