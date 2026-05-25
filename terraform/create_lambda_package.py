import os
import subprocess
import shutil
import zipfile
import sys

# Limpar se existir
if os.path.exists('lambda_build'):
    shutil.rmtree('lambda_build')

# Criar estrutura
os.makedirs('lambda_build/python/lib/python3.11/site-packages', exist_ok=True)

# Instalar dependências
subprocess.run([
    sys.executable, '-m', 'pip', 'install', 
    'pymysql',
    '-t', 'lambda_build/python/lib/python3.11/site-packages/'
], check=True)

# Copiar lambda_index.py
shutil.copy('lambda_index.py', 'lambda_build/')

# Criar ZIP
if os.path.exists('lambda_function_manual.zip'):
    os.remove('lambda_function_manual.zip')

with zipfile.ZipFile('lambda_function_manual.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk('lambda_build'):
        for file in files:
            file_path = os.path.join(root, file)
            arcname = os.path.relpath(file_path, 'lambda_build')
            z.write(file_path, arcname)

print("Lambda package created: lambda_function_manual.zip")

# Limpar
shutil.rmtree('lambda_build')