# ─────────────────────────────────────────
# IAM Role para EC2 acessar Secrets Manager
# ─────────────────────────────────────────
resource "aws_iam_role" "ec2_secrets_role" {
  name = "ec2-secrets-role-${var.environment}"

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
    Name        = "ec2-secrets-role-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

resource "aws_iam_role_policy" "ec2_secrets_policy" {
  name = "ec2-secrets-policy-${var.environment}"
  role = aws_iam_role.ec2_secrets_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-instance-profile-${var.environment}"
  role = aws_iam_role.ec2_secrets_role.name
}

# ─────────────────────────────────────────
# Cloud9 Environment
# ─────────────────────────────────────────
resource "aws_cloud9_environment_ec2" "main" {
  name          = "nodeapp-env-${var.environment}"
  description   = "Cloud9 environment para Node.js app"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id

  tags = {
    Name        = "cloud9-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }
}

# ─────────────────────────────────────────
# Lambda para inicializar banco de dados
# (Executa SQL para criar tabelas e dados)
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_role" {
  name = "lambda-db-init-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_secrets_policy" {
  name = "lambda-secrets-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_index.py"
  output_path = "${path.module}/lambda_function_generated.zip"
}

resource "aws_lambda_function" "db_init" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "db-init-${var.environment}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_index.handler"
  runtime          = "python3.11"
  timeout          = 60

  vpc_config {
    subnet_ids         = [aws_subnet.private_az1.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      SECRET_NAME = aws_secretsmanager_secret.db_credentials.name
      REGION      = var.aws_region
    }
  }

  tags = {
    Name        = "db-init-${var.environment}"
    Environment = var.environment
    Phase       = "3"
  }

  depends_on = [aws_db_instance.mysql]
}
# ─────────────────────────────────────────
# Security Group para Lambda (acesso ao RDS)
# ─────────────────────────────────────────
resource "aws_security_group" "lambda" {
  name        = "lambda-${var.environment}"
  description = "Security group para Lambda acessar RDS"
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

# Permitir Lambda acessar RDS
resource "aws_security_group_rule" "rds_from_lambda" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda.id
  security_group_id        = aws_security_group.rds.id
}

# ─────────────────────────────────────────
# Lambda Invocation (executa após RDS criado)
# ─────────────────────────────────────────
resource "aws_lambda_invocation" "db_init_invoke" {
  function_name = aws_lambda_function.db_init.function_name

  input = jsonencode({
    action = "init_db"
  })

  depends_on = [
    aws_db_instance.mysql,
    aws_secretsmanager_secret_version.db_credentials
  ]
}

# ─────────────────────────────────────────
# Outputs adicionais
# ─────────────────────────────────────────
output "cloud9_environment_id" {
  description = "ID do Cloud9 environment"
  value       = aws_cloud9_environment_ec2.main.id
}

output "lambda_function_name" {
  description = "Nome da função Lambda para inicializar DB"
  value       = aws_lambda_function.db_init.function_name
}