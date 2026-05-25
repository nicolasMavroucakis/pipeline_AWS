# ─────────────────────────────────────────
# Fase 2 — VPC + EC2 com app + MySQL local
# ─────────────────────────────────────────

environment   = "main"
aws_region    = "us-east-1"

# AMI Ubuntu 22.04 LTS — us-east-1
# Para outras regiões: https://cloud-images.ubuntu.com/locator/ec2/
ami_id        = "ami-0fc5d935ebf8bc3bc"

# Tipo de instância (free tier elegível)
instance_type = "t2.micro"

# 🔧 Descomente e substitua pelo seu key pair se quiser acesso SSH
key_name = "EC2_key_pair"
