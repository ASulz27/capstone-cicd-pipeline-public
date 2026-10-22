output "cicd_server_public_ip" {
  value = aws_instance.cicd_server.public_ip
}

output "web_server_public_ip" {
  value = aws_instance.web_server.public_ip
}

output "web_server_instance_id" {
  value = aws_instance.web_server.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

