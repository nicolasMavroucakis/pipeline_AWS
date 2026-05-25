# ─────────────────────────────────────────
# Fase 3 — VPC + EC2 com app + RDS MySQL
# ─────────────────────────────────────────

environment   = "main"
aws_region    = "us-east-1"
ami_id        = "ami-0fc5d935ebf8bc3bc"
instance_type = "t2.micro"
key_name      = "EC2_key_pair"

# RDS MySQL Credentials
db_master_username = "admin"
db_master_password = "Admin@12345"