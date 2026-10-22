resource "aws_instance" "cicd_server" {
  ami                         = "ami-066cddce9af49266b"
  user_data_replace_on_change = true
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.cicd_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.cicd_profile.name
  key_name                    = aws_key_pair.admin.key_name

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io awscli
    systemctl start docker 
    systemctl enable docker
    usermod -aG docker ubuntu
EOF

  tags = { Name = "${var.project_name}-cicd-server" }
}

resource "aws_instance" "web_server" {
  ami                         = "ami-027cb33fd1b59658e"
  user_data_replace_on_change = true
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.web_profile.name
  key_name                    = aws_key_pair.admin.key_name

  metadata_options {
    http_tokens   = "required" # enforces IMDSv2 — blocks the classic SSRF-to-credential-theft path
    http_endpoint = "enabled"
  }

  lifecycle {
    create_before_destroy = true
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOF
  #!/bin/bash
  cat > /etc/nginx/sites-available/app << 'NGINX'
  server {
      listen 80;
      server_name _;
      location / {
          proxy_pass http://127.0.0.1:5000;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
      }
  }
  NGINX
  ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
  rm -f /etc/nginx/sites-enabled/default
  systemctl restart nginx
EOF

  tags = { Name = "${var.project_name}-web-server" }
}



