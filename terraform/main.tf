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
    Phase       = "2"
  }
}

# ─────────────────────────────────────────
# Subnet Pública (AZ-1)
# ─────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "subnet-public-${var.environment}"
    Environment = var.environment
    Phase       = "2"
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
    Phase       = "2"
  }
}

# ─────────────────────────────────────────
# Route Table — Subnet Pública → IGW
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
    Phase       = "2"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────
# Security Group — EC2
# Porta 80: HTTP (aplicação web)
# Porta 22: SSH (acesso remoto)
# Porta 3306: MySQL (local, acessível de dentro da VPC)
# ─────────────────────────────────────────
resource "aws_security_group" "ec2" {
  name        = "sg-ec2-${var.environment}"
  description = "Security group da EC2 - fase 2 (app + MySQL local)"
  vpc_id      = aws_vpc.main.id

  # HTTP — aplicação web
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH — acesso remoto
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MySQL — acesso local (opcional, apenas para debug)
  ingress {
    description = "MySQL local"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Apenas de dentro da VPC
  }

  # Egress — permitir tudo
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "sg-ec2-${var.environment}"
    Environment = var.environment
    Phase       = "2"
  }
}

# ─────────────────────────────────────────
# EC2 — Ubuntu com app + MySQL local
# Script oficial do AWS Academy (UserdataScript-phase-2.sh)
# ─────────────────────────────────────────
resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_name != "" ? var.key_name : null

  # Script de inicialização — instala app + MySQL + credenciais
  user_data = base64encode(<<EOF
#!/bin/bash -xe
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y nodejs unzip wget npm mysql-server curl jq

# Baixar e descompactar o código da aplicação
wget https://aws-tc-largeobjects.s3.us-west-2.amazonaws.com/CUR-TF-200-ACCAP1-1-91571/1-lab-capstone-project-1/code.zip -P /home/ubuntu
cd /home/ubuntu
unzip code.zip -x "resources/codebase_partner/node_modules/*"
cd resources/codebase_partner
npm install aws aws-sdk

# Criar usuário e banco de dados do MySQL
mysql -u root -e "CREATE USER 'nodeapp' IDENTIFIED WITH mysql_native_password BY 'student12';"
mysql -u root -e "GRANT all privileges on *.* to 'nodeapp'@'%';"
mysql -u root -e "CREATE DATABASE STUDENTS;"
mysql -u root -e "USE STUDENTS; CREATE TABLE students(id INT NOT NULL AUTO_INCREMENT, name VARCHAR(255) NOT NULL, address VARCHAR(255) NOT NULL, city VARCHAR(255) NOT NULL, state VARCHAR(255) NOT NULL, email VARCHAR(255) NOT NULL, phone VARCHAR(100) NOT NULL, PRIMARY KEY (id));"

# Configurar MySQL para aceitar conexões remotas
sed -i 's/.*bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl enable mysql
service mysql restart

# Obter IP privado da instância
PRIVATE_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)

# Definir variáveis de ambiente
export APP_DB_HOST=$PRIVATE_IP
export APP_DB_USER=nodeapp
export APP_DB_PASSWORD=student12
export APP_DB_NAME=STUDENTS
export APP_PORT=80

# Persistir variáveis de ambiente
cat > /etc/environment << ENVEOF
APP_DB_HOST=$PRIVATE_IP
APP_DB_USER=nodeapp
APP_DB_PASSWORD=student12
APP_DB_NAME=STUDENTS
APP_PORT=80
ENVEOF

# Iniciar a aplicação em background
npm start &

# Criar script de restart automático
cat > /etc/rc.local << RCEOF
#!/bin/bash -xe
source /etc/environment
cd /home/ubuntu/resources/codebase_partner
npm start
RCEOF
chmod +x /etc/rc.local
EOF
  )

  tags = {
    Name        = "ec2-app-${var.environment}"
    Environment = var.environment
    Phase       = "2"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
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

output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.main.id
}

output "subnet_public_id" {
  description = "ID da subnet pública"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "ID do Security Group da EC2"
  value       = aws_security_group.ec2.id
}

output "ec2_instance_id" {
  description = "ID da instância EC2"
  value       = aws_instance.app.id
}
