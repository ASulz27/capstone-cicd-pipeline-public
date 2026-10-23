# Runbook: replicate, run and tear down the capstone

Terraform, Packer and GitHub Actions: a commit to main builds a Docker image, pushes it to ECR and deploys it to an EC2 web server over AWS SSM (no SSH). It replaces an earlier Forgejo + Jenkins design.

Reference project, not production-ready. Actions are disabled in this repo and it holds no AWS secrets. AMI IDs and the state bucket are account-specific. Running it bills your AWS account.

How it works
push to main -> GitHub Actions
  terraform.yml   plan on PR, apply on push ("production" environment)
  deploy.yml      self-hosted runner: build image (tag = commit SHA) -> ECR -> SSM Run Command -> web instance
Internet :80 -> nginx -> gunicorn container (127.0.0.1:5000)

Two t3.micro instances (CI/CD server, web server) in one VPC and public subnet. Terraform state lives in S3 with DynamoDB locking.

Quick start
Create an S3 bucket (versioning, encryption, public access blocked) and a DynamoDB table capstone-cicd-pipeline-tf-lock with key LockID.
cp backend.hcl.example backend.hcl (set your bucket), cp terraform.tfvars.example terraform.tfvars, then terraform init -backend-config=backend.hcl.
Run packer build for each template in packer/, and put the resulting AMI IDs in instances.tf.
terraform plan -out=tfplan && terraform apply tfplan
Register a self-hosted runner on the CI/CD instance (manual, through SSM Session Manager).
Enable Actions, add AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, create a production environment with required reviewers, then push to main. Check it with curl "http://$(terraform output -raw web_server_public_ip)/".

Tear down with terraform destroy after removing the prevent_destroy blocks. Delete the AMIs and the state backend separately.

Hardening

No SSH ingress (SSM only), IMDSv2, encrypted volumes, scoped IAM roles, ECR scan on push, encrypted and locked remote state, prevent_destroy on the ECR repo and IAM roles, and apply gated behind a production environment.

Known gaps

Stored IAM keys (move to OIDC), apply does not use the reviewed plan, CI runs plan only, the container runs as root with no healthcheck, HTTP only, and rollback is manual (redeploy an earlier image SHA).

The approval gates (pause, reject, approve) were tested in gate-lab. Full detail is in the runbook.