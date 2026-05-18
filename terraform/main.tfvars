# ─── Ambiente: MAIN (fase 2) ───────────────
environment   = "main"
aws_region    = "sa-east-1"   # 🔧 região do seu lab

# AMI Ubuntu 22.04 LTS — us-east-1
# Para outras regiões consulte: https://cloud-images.ubuntu.com/locator/ec2/
ami_id        = "ami-0fc5d935ebf8bc3bc"

instance_type = "t2.micro"    # free tier elegível

# key_name    = "meu-key-pair"  # 🔧 descomente se quiser acesso SSH
