import json
import boto3
import pymysql
import os

secrets_client = boto3.client('secretsmanager', region_name=os.environ['REGION'])

def handler(event, context):
    try:
        # Obter credenciais do Secrets Manager
        secret = secrets_client.get_secret_value(SecretId=os.environ['SECRET_NAME'])
        creds = json.loads(secret['SecretString'])
        
        # Conectar ao RDS
        connection = pymysql.connect(
            host=creds['host'].split(':')[0],
            user=creds['username'],
            password=creds['password'],
            database=creds['dbname']
        )
        
        cursor = connection.cursor()
        
        # Criar tabela STUDENTS
        sql = """
        CREATE TABLE IF NOT EXISTS students (
            id INT NOT NULL AUTO_INCREMENT,
            name VARCHAR(255) NOT NULL,
            address VARCHAR(255) NOT NULL,
            city VARCHAR(255) NOT NULL,
            state VARCHAR(255) NOT NULL,
            email VARCHAR(255) NOT NULL,
            phone VARCHAR(100) NOT NULL,
            PRIMARY KEY (id)
        );
        """
        
        cursor.execute(sql)
        connection.commit()
        
        cursor.close()
        connection.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps('Database initialized successfully')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }