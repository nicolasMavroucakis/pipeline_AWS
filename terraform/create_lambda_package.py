import os
import subprocess
import shutil
import zipfile
import sys

# Limpar se existir
if os.path.exists('lambda_build'):
    shutil.rmtree('lambda_build')

# Criar estrutura na raiz (não em site-packages)
os.makedirs('lambda_build', exist_ok=True)

# Instalar dependências diretamente na raiz
subprocess.run([
    sys.executable, '-m', 'pip', 'install', 
    'pymysql',
    '-t', 'lambda_build/'
], check=True)

# Copiar lambda_index.py para a raiz
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
print("Contents:")
with zipfile.ZipFile('lambda_function_manual.zip', 'r') as z:
    for name in z.namelist():
        print(f"  - {name}")

# Limpar
shutil.rmtree('lambda_build')