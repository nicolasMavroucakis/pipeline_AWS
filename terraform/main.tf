# ─────────────────────────────────────────
# Variáveis
# ─────────────────────────────────────────
variable "environment" {
  description = "Nome do ambiente"
  type        = string
}

variable "aws_region" {
  description = "Região AWS"
  type        = string
}

variable "instance_type" {
  description = "Tipo da instância EC2"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "AMI Ubuntu 22.04 LTS"
  type        = string
}

variable "key_name" {
  description = "Nome do Key Pair para acesso SSH (opcional)"
  type        = string
  default     = ""
}

variable "db_master_username" {
  description = "Usuário master do RDS"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_master_password" {
  description = "Senha master do RDS"
  type        = string
  sensitive   = true
}

# ─────────────────────────────────────────
# Provider
# ─────────────────────────────────────────
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "awsimt2026nicolasgustavo"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# ─────────────────────────────────────────
# VPC
# ─────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "vpc-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

# ─────────────────────────────────────────
# Subnet Pública (AZ-1) — para EC2 e NAT Gateway
# ─────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "subnet-public-${var.environment}"
    Environment = var.environment
    Phase       = "3"
    Type        = "Public"
  }
}

# ─────────────────────────────────────────
# Subnets Privadas (AZ-1 e AZ-2) — para RDS
# ─────────────────────────────────────────
resource "aws_subnet" "private_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "subnet-private-az1-${var.environment}"
    Environment = var.environment
    Phase       = "3"
    Type        = "Private"
  }
}

resource "aws_subnet" "private_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name        = "subnet-private-az2-${var.environment}"
    Environment = var.environment
    Phase       = "3"
    Type        = "Private"
  }
}

# ─────────────────────────────────────────
# Internet Gateway
# ─────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "igw-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

# ─────────────────────────────────────────
# Elastic IP para NAT Gateway
# ─────────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "eip-nat-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }

  depends_on = [aws_internet_gateway.igw]
}

# ─────────────────────────────────────────
# NAT Gateway — na Subnet Pública
# ─────────────────────────────────────────
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name        = "nat-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }

  depends_on = [aws_internet_gateway.igw]
}

# ─────────────────────────────────────────
# Route Table Pública — Subnet Pública → IGW
# ─────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "rt-public-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────
# Route Table Privada — Subnets Privadas → NAT Gateway
# ─────────────────────────────────────────
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name        = "rt-private-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

resource "aws_route_table_association" "private_az1" {
  subnet_id      = aws_subnet.private_az1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_az2" {
  subnet_id      = aws_subnet.private_az2.id
  route_table_id = aws_route_table.private.id
}

# ─────────────────────────────────────────
# Security Group — EC2 (apenas app Node.js)
# Porta 80: HTTP (aplicação web)
# Porta 22: SSH (acesso remoto)
# ─────────────────────────────────────────
resource "aws_security_group" "ec2" {
  name        = "ec2-${var.environment}-3"
  description = "Security group da EC2 - fase 3 (apenas app Node.js)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ec2-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

# ─────────────────────────────────────────
# Security Group — RDS (MySQL)
# Acessa apenas da EC2
# ─────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "rds-${var.environment}-3"
  description = "Security group do RDS - fase 3 (MySQL)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  ingress {
    description     = "MySQL from Lambda"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "rds-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

# ─────────────────────────────────────────
# DB Subnet Group — para RDS em subnets privadas
# ─────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "db-subnet-group-${var.environment}"
  subnet_ids = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]

  tags = {
    Name        = "db-subnet-group-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

# ─────────────────────────────────────────
# RDS MySQL Instance
# ─────────────────────────────────────────
resource "aws_db_instance" "mysql" {
  identifier            = "mysql-${var.environment}"
  engine                = "mysql"
  engine_version        = "8.0"
  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  storage_type          = "gp2"
  storage_encrypted     = false

  db_name  = "STUDENTS"
  username = var.db_master_username
  password = var.db_master_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name        = "mysql-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

# ─────────────────────────────────────────
# AWS Secrets Manager — Credenciais do RDS
# ─────────────────────────────────────────
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "rds/${var.environment}/db-credentials"
  description             = "Credenciais do banco de dados RDS"
  recovery_window_in_days = 7

  tags = {
    Name        = "db-credentials-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    # Para o Node.js:
    user     = var.db_master_username
    db       = "STUDENTS"
    
    # Para a Lambda (Python):
    username = var.db_master_username
    dbname   = "STUDENTS"
    
    # Comuns a ambos:
    password = var.db_master_password
    engine   = "mysql"
    host     = aws_db_instance.mysql.endpoint
    port     = 3306
  })
}

# ─────────────────────────────────────────
# Usar IAM Profile existente do Lab
# ─────────────────────────────────────────
data "aws_iam_instance_profile" "lab_profile" {
  name = "LabInstanceProfile"
}

# ─────────────────────────────────────────
# EC2 — Ubuntu com aplicação Node.js
# Conecta ao RDS via Secrets Manager
# ─────────────────────────────────────────
resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_name != "" ? var.key_name : null
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name

  user_data = base64encode(<<EOF
#!/bin/bash -xe
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y nodejs unzip wget npm curl jq awscli mysql-client

# Baixar e descompactar o código da aplicação
wget https://aws-tc-largeobjects.s3.us-west-2.amazonaws.com/CUR-TF-200-ACCAP1-1-91571/1-lab-capstone-project-1/code.zip -P /home/ubuntu
cd /home/ubuntu
unzip code.zip -x "resources/codebase_partner/node_modules/*"
cd resources/codebase_partner
npm install aws aws-sdk

# Script para obter credenciais do Secrets Manager e iniciar a app
cat > /home/ubuntu/start-app.sh << 'STARTEOF'
#!/bin/bash
SECRET_NAME="rds/${var.environment}/db-credentials"
REGION="${var.aws_region}"

# Obter secret do Secrets Manager
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --query 'SecretString' \
  --output text)

# Extrair credenciais
export APP_DB_HOST=$(echo $SECRET | jq -r '.host' | cut -d: -f1)
export APP_DB_USER=$(echo $SECRET | jq -r '.user')        # mudou de .username para .user
export APP_DB_PASSWORD=$(echo $SECRET | jq -r '.password')
export APP_DB_NAME=$(echo $SECRET | jq -r '.db')           # mudou de .dbname para .db
export APP_PORT=80


# Iniciar a aplicação
cd /home/ubuntu/resources/codebase_partner
npm start
STARTEOF

chmod +x /home/ubuntu/start-app.sh

# Criar script de restart automático via systemd
cat > /etc/systemd/system/nodeapp.service << 'SERVICEEOF'
[Unit]
Description=Node.js Student Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/ubuntu/resources/codebase_partner
ExecStart=/home/ubuntu/start-app.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable nodeapp.service
systemctl start nodeapp.service
EOF
  )

  tags = {
    Name        = "ec2-app-${var.environment}-3"
    Environment = var.environment
    Phase       = "3"
    ManagedBy   = "Terraform"
  }

  depends_on = [aws_secretsmanager_secret_version.db_credentials]

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────
# Security Group — Lambda 
# ─────────────────────────────────────────
resource "aws_security_group" "lambda" {
  name        = "lambda-${var.environment}-3"
  description = "Security group da Lambda - fase 3"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "lambda-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

# ─────────────────────────────────────────
# Usar IAM Role existente do Lab para Lambda
# ─────────────────────────────────────────
data "aws_iam_role" "lambda_role" {
  name = "LabRole"
}


# ─────────────────────────────────────────
# Lambda Function — Inicializa banco de dados
# ─────────────────────────────────────────
resource "aws_lambda_function" "db_init" {
  filename            = "lambda_function_manual.zip"
  source_code_hash    = filebase64sha256("lambda_function_manual.zip")
  function_name       = "db-init-${var.environment}"
  role                = data.aws_iam_role.lambda_role.arn
  handler             = "lambda_index.handler"
  runtime             = "python3.11"
  timeout             = 60

  vpc_config {
    subnet_ids         = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      SECRET_NAME = aws_secretsmanager_secret.db_credentials.name
      REGION      = var.aws_region
    }
  }

  tags = {
    Name        = "db-init-${var.environment}-2"
    Environment = var.environment
    Phase       = "3"
  }

  depends_on = [aws_secretsmanager_secret_version.db_credentials]
}

# ─────────────────────────────────────────
# Invocação automática da Lambda
# ─────────────────────────────────────────
resource "aws_lambda_invocation" "db_init" {
  function_name = aws_lambda_function.db_init.function_name

  input = jsonencode({
    action    = "initialize_db"
    timestamp = timestamp() # 💡 Força o re-run neste apply com um input novo
  })

  depends_on = [
    aws_db_instance.mysql,
    aws_secretsmanager_secret_version.db_credentials
  ]
}

# ─────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────
output "ec2_public_ip" {
  description = "IP público da EC2 — use para acessar a aplicação"
  value       = aws_instance.app.public_ip
}

output "ec2_public_dns" {
  description = "DNS público da EC2"
  value       = aws_instance.app.public_dns
}

output "app_url" {
  description = "URL da aplicação — abra no browser"
  value       = "http://${aws_instance.app.public_ip}"
}

output "rds_endpoint" {
  description = "Endpoint do RDS MySQL"
  value       = aws_db_instance.mysql.endpoint
}

output "rds_address" {
  description = "Endereço do RDS (sem porta)"
  value       = aws_db_instance.mysql.address
}

output "rds_port" {
  description = "Porta do RDS"
  value       = aws_db_instance.mysql.port
}

output "secret_name" {
  description = "Nome da secret no Secrets Manager"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.main.id
}

output "nat_gateway_ip" {
  description = "IP público do NAT Gateway"
  value       = aws_eip.nat.public_ip
}

output "ec2_instance_id" {
  description = "ID da instância EC2"
  value       = aws_instance.app.id
}

output "security_group_ec2_id" {
  description = "ID do Security Group da EC2"
  value       = aws_security_group.ec2.id
}

output "security_group_rds_id" {
  description = "ID do Security Group do RDS"
  value       = aws_security_group.rds.id
}

output "subnet_public_id" {
  description = "ID da subnet pública"
  value       = aws_subnet.public.id
}

output "subnet_private_az1_id" {
  description = "ID da subnet privada AZ-1"
  value       = aws_subnet.private_az1.id
}

output "subnet_private_az2_id" {
  description = "ID da subnet privada AZ-2"
  value       = aws_subnet.private_az2.id
}