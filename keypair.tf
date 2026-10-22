resource "tls_private_key" "admin" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.project_name}-admin-key"
  public_key = tls_private_key.admin.public_key_openssh
}

resource "local_file" "admin_pem" {
  content         = tls_private_key.admin.private_key_pem
  filename        = "${path.module}/${var.project_name}-admin-key.pem"
  file_permission = "0400"
}
