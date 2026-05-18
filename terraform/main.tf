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
  description = "AMI Ubuntu — us-east-1: ami-0fc5d935ebf8bc3bc"
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
  }
}

# ─────────────────────────────────────────
# Subnet pública (AZ-1)
# ─────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "subnet-public-${var.environment}"
    Environment = var.environment
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
  }
}

# ─────────────────────────────────────────
# Route Table — subnet pública → IGW
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
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────
# Security Group — EC2
# Porta 80: app roda na 80 conforme o script do lab (APP_PORT=80)
# Porta 22: SSH para debug
# ─────────────────────────────────────────
resource "aws_security_group" "ec2" {
  name        = "ec2-${var.environment}"
  description = "Security group da EC2 - fase 2"
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
  }
}

# ─────────────────────────────────────────
# EC2 — Ubuntu com app + banco local
# Script oficial do lab (UserdataScript-phase-2.sh)
# ─────────────────────────────────────────
resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_name != "" ? var.key_name : null

  user_data = <<-EOF
    #!/bin/bash -xe
    apt update -y
    apt install nodejs unzip wget npm mysql-server -y
    wget https://aws-tc-largeobjects.s3.us-west-2.amazonaws.com/CUR-TF-200-ACCAP1-1-91571/1-lab-capstone-project-1/code.zip -P /home/ubuntu
    cd /home/ubuntu
    unzip code.zip -x "resources/codebase_partner/node_modules/*"
    cd resources/codebase_partner
    npm install aws aws-sdk
    mysql -u root -e "CREATE USER 'nodeapp' IDENTIFIED WITH mysql_native_password BY 'student12'";
    mysql -u root -e "GRANT all privileges on *.* to 'nodeapp'@'%';"
    mysql -u root -e "CREATE DATABASE STUDENTS;"
    mysql -u root -e "USE STUDENTS; CREATE TABLE students(
                id INT NOT NULL AUTO_INCREMENT,
                name VARCHAR(255) NOT NULL,
                address VARCHAR(255) NOT NULL,
                city VARCHAR(255) NOT NULL,
                state VARCHAR(255) NOT NULL,
                email VARCHAR(255) NOT NULL,
                phone VARCHAR(100) NOT NULL,
                PRIMARY KEY ( id ));"
    sed -i 's/.*bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
    systemctl enable mysql
    service mysql restart
    export APP_DB_HOST=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
    export APP_DB_USER=nodeapp
    export APP_DB_PASSWORD=student12
    export APP_DB_NAME=STUDENTS
    export APP_PORT=80
    npm start &
    echo '#!/bin/bash -xe
    cd /home/ubuntu/resources/codebase_partner
    export APP_PORT=80
    npm start' > /etc/rc.local
    chmod +x /etc/rc.local
  EOF

  tags = {
    Name        = "ec2-app-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────
output "ec2_public_ip" {
  description = "IP público da EC2"
  value       = aws_instance.app.public_ip
}

output "ec2_public_dns" {
  description = "DNS público da EC2"
  value       = aws_instance.app.public_dns
}

output "app_url" {
  description = "URL da aplicação — acesse no browser"
  value       = "http://${aws_instance.app.public_ip}"
}
EOF
