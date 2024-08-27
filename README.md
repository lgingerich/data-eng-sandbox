# data-eng-sandbox
Self-learning for various data engineering technologies



# Instructions

## 1. Setup Airflow
    ```bash
    ./airflow_manager.sh setup
    ```

## 2. Access Airflow UI
    ```bash
    kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow
    ```

## 3. Shutdown Airflow
    ```bash
    ./airflow_manager.sh teardownß
    ```