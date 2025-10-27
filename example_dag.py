"""
Example DAG for testing Airflow 3.1.0 deployment
Author: Mithun Cheriyath (@mcheriyath)
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

# Default arguments for the DAG
default_args = {
    'owner': 'mcheriyath',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Define the DAG
dag = DAG(
    'example_airflow_test',
    default_args=default_args,
    description='A simple example DAG to test Airflow 3.1.0',
    schedule_interval='@daily',
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['example', 'test', 'airflow-3.1.0'],
)

def print_hello():
    """Simple Python function to print hello message"""
    print("🚁 Hello from Airflow 3.1.0!")
    print("🎯 DAG is running successfully on Minikube!")
    return "Success!"

def print_system_info():
    """Print system information"""
    import platform
    import sys
    
    print(f"🐍 Python version: {sys.version}")
    print(f"🖥️  Platform: {platform.platform()}")
    print(f"⚙️  Processor: {platform.processor()}")
    print("✨ Airflow 3.1.0 test completed successfully!")
    return "System info collected!"

# Task 1: Print hello message
hello_task = PythonOperator(
    task_id='print_hello',
    python_callable=print_hello,
    dag=dag,
)

# Task 2: Print system info
system_info_task = PythonOperator(
    task_id='print_system_info',
    python_callable=print_system_info,
    dag=dag,
)

# Task 3: Run a bash command
bash_task = BashOperator(
    task_id='run_bash_command',
    bash_command='echo "🎉 Bash task completed successfully!" && date',
    dag=dag,
)

# Task 4: Check Airflow version
version_check_task = BashOperator(
    task_id='check_airflow_version',
    bash_command='airflow version',
    dag=dag,
)

# Define task dependencies
hello_task >> [system_info_task, bash_task]
[system_info_task, bash_task] >> version_check_task