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

variable "lambda_timeout" {
  description = "Timeout da Lambda em segundos"
  type        = number
  default     = 30
}

variable "lambda_memory" {
  description = "Memória da Lambda em MB"
  type        = number
  default     = 128
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
    bucket = "meu-bucket-tfstate"   # 🔧 Altere para seu bucket
    region = "sa-east-1"
    # a "key" é injetada dinamicamente pelo workflow do GitHub Actions
  }
}

provider "aws" {
  region = var.aws_region
}

# ─────────────────────────────────────────
# IAM Role da Lambda
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ─────────────────────────────────────────
# CloudWatch Log Group
# ─────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/minha-lambda-${var.environment}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# Lambda Function
# ─────────────────────────────────────────
resource "aws_lambda_function" "minha_lambda" {
  function_name = "minha-lambda-${var.environment}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  filename      = "lambda.zip"        # 🔧 Seu arquivo zip com o código
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  environment {
    variables = {
      ENV    = var.environment
      REGION = var.aws_region
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic
  ]

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────
output "lambda_name" {
  value = aws_lambda_function.minha_lambda.function_name
}

output "lambda_arn" {
  value = aws_lambda_function.minha_lambda.arn
}
