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

variable "db_username" {
  description = "Username do RDS"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Senha do RDS (mínimo 8 caracteres)"
  type        = string
  default     = "Admin12345678"
  sensitive   = true
}

variable "db_name" {
  description = "Nome do banco de dados"
  type        = string
  default     = "STUDENTS"
}

variable "asg_min_size" {
  description = "Mínimo de instâncias no Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Máximo de instâncias no Auto Scaling Group"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Número desejado de instâncias"
  type        = number
  default     = 2
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
    Phase       = "4"
  }
}

# ─────────────────────────────────────────
# SUBNETS PÚBLICAS (ALB + NAT Gateway)
# ─────────────────────────────────────────
resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "subnet-public-az1-${var.environment}"
    Environment = var.environment
    Phase       = "4"
  }
}

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name        = "subnet-public-az2-${var.environment}"
    Environment = var.environment
    Phase       = "4"
  }
}

# ─────────────────────────────────────────
# SUBNETS PRIVADAS (EC2 do ASG + RDS)
# ─────────────────────────────────────────
resource "aws_subnet" "private_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "subnet-private-az1-${var.environment}"
    Environment = var.environment
    Phase       = "4"
  }
}

resource "aws_subnet" "private_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name        = "subnet-private-az2-${var.environment}"
    Environment = var.environment
    Phase       = "4"
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
    Phase       = "4"
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
    Phase       = "4"
  }

  depends_on = [aws_internet_gateway.igw]
}

# ─────────────────────────────────────────
# NAT Gateway (em subnet pública AZ-1)
# ─────────────────────────────────────────
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_az1.id

  tags = {
    Name        = "nat-${var.environment}"
    Environment = var.environment
    Phase       = "4"
  }

  depends_on = [aws_internet_gateway.igw]
}

# ─────────────────────────────────────────
# Route Table — Subnets Públicas
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
    Phase       = "4"
  }
}

resource "aws_route_table_association" "public_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────
# Route Table — Subnets Privadas
# (saída via NAT Gateway)
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
    Phase       = "4"
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
# Security Group — ALB
# ─────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "alb-${var.environment}-4"
  description = "Security group do ALB - fase 4"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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
    Name        = "alb-${var.environment}"
    Environment = var.environment
    Phase       = "4"
  }
}

# ─────────────────────────────────────────
# Security Group — EC2 (ASG)
# ─────────────────────────────────────────
resource "aws_security_group" "ec2" {
  name        = "ec2-${var.environment}-4"
  description = "Security group da EC2 - fase 4 (ASG)"
  vpc_id      = aws_vpc.main.id

  # Tráfego do ALB
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # SSH (opcional)
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
    Phase       = "4"
  }
}

# ─────────────────────────────────────────
# Security Group — RDS
# ─────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "rds-${var.environment}-4"
  description = "Security group do RDS - fase 4"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
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
    Phase       = "4"
  }
}

# ─────────────────────────────────────────
# DB Subnet Group
# ─────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "db-subnet-group-${var.environment}"
  subnet_ids = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]

  tags = {
    Name        = "db-subnet-group-${var.environment}"
    Environment = var.environment
    Phase       = "4"
  }
}

# ─────────────────────────────────────────
# RDS MySQL — Multi-AZ
# ─────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier              = "mysql-${var.environment}"
  engine                  = "mysql"
  engine_version          = "8.0.45"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp2"
  username                = var.db_username
  password                = var.db_password
  db_name                 = var.db_name
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  multi_az                = true
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 7

  tags = {
    Name        = "rds-${var.environment}"
    Environment = var.environment
    Phase       = "4"
  }
}

# ─────────────────────────────────────────
# Secrets Manager
# ─────────────────────────────────────────
resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "rds-credentials-${var.environment}"
  recovery_window_in_days = 7

  tags = {
    Name        = "rds-credentials-${var.environment}"
    Environment = var.environment
    Phase       = "4"
  }
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    engine   = "mysql"
    host     = aws_db_instance.main.endpoint
    port     = 3306
    dbname   = var.db_name
  })
}

# ─────────────────────────────────────────
# IAM Role para EC2 (acesso a Secrets Manager)
# ─────────────────────────────────────────
resource "aws_iam_role" "ec2_role" {
  name = "ec2-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Phase       = "4"
  }
}

resource "aws_iam_role_policy" "ec2_secrets_policy" {
  name = "ec2-secrets-policy-${var.environment}"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.rds_credentials.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile-${var.environment}"
  role = aws_iam_role.ec2_role.name
}

# ─────────────────────────────────────────
# Launch Template para o ASG
# ─────────────────────────────────────────
resource "aws_launch_template" "app" {
  name_prefix   = "lt-${var.environment}-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(<<EOF
#!/bin/bash -xe
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y nodejs unzip wget npm curl jq

# Instalar código da app
wget https://aws-tc-largeobjects.s3.us-west-2.amazonaws.com/CUR-TF-200-ACCAP1-1-91571/1-lab-capstone-project-1/code.zip -P /home/ubuntu
cd /home/ubuntu
unzip code.zip -x "resources/codebase_partner/node_modules/*"
cd resources/codebase_partner
npm install aws aws-sdk

# Buscar credenciais do Secrets Manager
REGION=${var.aws_region}
SECRET_NAME=rds-credentials-${var.environment}
SECRET=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --region $REGION --query SecretString --output text)

# Extrair valores
DB_HOST=$(echo $SECRET | jq -r '.host' | sed 's/:3306//')
DB_USER=$(echo $SECRET | jq -r '.username')
DB_PASSWORD=$(echo $SECRET | jq -r '.password')
DB_NAME=$(echo $SECRET | jq -r '.dbname')

# Exportar variáveis
export APP_DB_HOST=$DB_HOST
export APP_DB_USER=$DB_USER
export APP_DB_PASSWORD=$DB_PASSWORD
export APP_DB_NAME=$DB_NAME
export APP_PORT=80

# Persistir variáveis
cat > /etc/environment << ENVEOF
APP_DB_HOST=$DB_HOST
APP_DB_USER=$DB_USER
APP_DB_PASSWORD=$DB_PASSWORD
APP_DB_NAME=$DB_NAME
APP_PORT=80
ENVEOF

# Criar serviço systemd para restart automático
cat > /etc/systemd/system/nodeapp.service << SVCEOF
[Unit]
Description=Node.js Student Records Application
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/resources/codebase_partner
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=5s
EnvironmentFile=/etc/environment

[Install]
WantedBy=multi-user.target
SVCEOF

# Ativar e iniciar serviço
systemctl daemon-reload
systemctl enable nodeapp.service
systemctl start nodeapp.service
EOF

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "ec2-asg-${var.environment}"
      Environment = var.environment
      Phase       = "4"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────
# Application Load Balancer
# ─────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_az1.id, aws_subnet.public_az2.id]

  tags = {
    Name        = "alb-${var.environment}"
    Environment = var.environment
    Phase       = "4"
  }
}

# ─────────────────────────────────────────
# Target Group
# ─────────────────────────────────────────
resource "aws_lb_target_group" "app" {
  name        = "tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = {
    Name        = "tg-${var.environment}"
    Environment = var.environment
    Phase       = "4"
  }
}

# ─────────────────────────────────────────
# ALB Listener
# ─────────────────────────────────────────
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ─────────────────────────────────────────
# Auto Scaling Group
# ─────────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name                = "asg-${var.environment}"
  vpc_zone_identifier = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 60

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "ec2-asg-${var.environment}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Phase"
    value               = "4"
    propagate_at_launch = true
  }

  depends_on = [
    aws_lb_listener.app,
    aws_db_instance.main
  ]
}

# ─────────────────────────────────────────
# Scaling Policy — Target Tracking (CPU)
# ─────────────────────────────────────────
resource "aws_autoscaling_policy" "cpu" {
  name                   = "asg-cpu-${var.environment}"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0  # Escala quando CPU > 60%
  }
}

# ─────────────────────────────────────────
# Scaling Policy — Request Count
# ─────────────────────────────────────────
resource "aws_autoscaling_policy" "requests" {
  name                   = "asg-requests-${var.environment}"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
    }
    target_value = 1000.0  # Escala quando > 1000 req/min por instância
  }
}

# ─────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────
output "alb_dns_name" {
  description = "DNS do ALB — acesse a aplicação por aqui"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "URL da aplicação via ALB"
  value       = "http://${aws_lb.main.dns_name}"
}

output "asg_name" {
  description = "Nome do Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "asg_min_size" {
  description = "Mínimo de instâncias no ASG"
  value       = aws_autoscaling_group.app.min_size
}

output "asg_max_size" {
  description = "Máximo de instâncias no ASG"
  value       = aws_autoscaling_group.app.max_size
}

output "asg_desired_capacity" {
  description = "Capacidade desejada do ASG"
  value       = aws_autoscaling_group.app.desired_capacity
}

output "rds_endpoint" {
  description = "Endpoint do RDS"
  value       = aws_db_instance.main.endpoint
}

output "target_group_arn" {
  description = "ARN do Target Group"
  value       = aws_lb_target_group.app.arn
}
