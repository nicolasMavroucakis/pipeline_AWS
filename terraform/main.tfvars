# ─────────────────────────────────────────
# Fase 4 — ALB + Auto Scaling + Multi-AZ
# ─────────────────────────────────────────

environment = "main"
aws_region  = "us-east-1"

# AMI Ubuntu 22.04 LTS
ami_id        = "ami-0fc5d935ebf8bc3bc"
instance_type = "t2.micro"

key_name = "fasefinal"  # 🔧 descomente para acesso SSH

# Credenciais do RDS
db_username = "admin"
db_password = "Admin12345678"
db_name     = "STUDENTS"

# Auto Scaling Group
asg_min_size         = 2    # Sempre 1 por AZ
asg_desired_capacity = 2    # 1 por AZ normalmente
asg_max_size         = 4    # Máximo 2 por AZ
