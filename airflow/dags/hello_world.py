from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2023, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'hello_world',
    default_args=default_args,
    description='A simple hello world DAG',
    schedule_interval=timedelta(days=1),
)

t1 = BashOperator(
    task_id='print_hello',
    bash_command='echo Hello',
    dag=dag,
)

t2 = BashOperator(
    task_id='print_world',
    bash_command='echo World',
    dag=dag,
)

t1 >> t2