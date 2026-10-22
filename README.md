Claude
































Runbook · MD
Capstone: CI/CD pipeline on AWS
A two-tier AWS environment provisioned with Terraform, with AMIs built by Packer, and a GitHub Actions pipeline that builds a Docker image, pushes it to ECR and deploys it to a web server over AWS SSM (no SSH). It replaces an earlier Forgejo + Jenkins design.

Status: reference implementation / lab project, not production-ready.

GitHub Actions are disabled in this repository and it holds no AWS secrets. See Run the pipeline before enabling anything.
AMI IDs and the state bucket are account-specific. You must build your own images and create your own backend (steps 1 and 2).
Creating this stack bills your AWS account. Destroy it when you are done (Tear down).
1. What it builds
One VPC (10.0.0.0/16) with a single public subnet (10.0.1.0/24) in the region's first available Availability Zone.
Two t3.micro instances: a CI/CD server (self-hosted GitHub Actions runner) and a web server.
nginx on the web server proxies port 80 to a gunicorn container on 127.0.0.1:5000.
A small Flask app (app/) that returns {"message":"Hello from the pipeline!","version":"v1"} on /.
An ECR repository for the app image (scan on push; images tagged with the commit SHA).
Remote Terraform state in S3 with DynamoDB locking.
2. Architecture
 push to main
      |
      v
 GitHub Actions
  |-- terraform.yml  (GitHub-hosted)   plan on PR, apply on push -> "production" environment
  '-- deploy.yml     (self-hosted runner on the CI/CD instance)
         1. find the web instance by its Name tag
         2. docker build ./app, tag = commit SHA, push to ECR
         3. scripts/deploy.py -> SSM Run Command on the web instance
                                  (ECR login, docker pull, stop/remove old container, run new one)

 Internet --:80--> [ web instance: nginx --> 127.0.0.1:5000 --> gunicorn container ]
 No SSH ingress. Admin access is via SSM Session Manager.
Stack: Terraform >= 1.7.0 (aws ~> 5.0, tls ~> 4.0, local ~> 2.5), Packer, Docker (python:3.12-slim, Flask 3.0.3, gunicorn 22.0.0), GitHub Actions, AWS CLI, Python 3.

3. Repository layout
.
|-- app/                    Flask app, requirements.txt, Dockerfile (gunicorn)
|-- packer/                 AMI templates: cicd-server.pkr.hcl, web-server.pkr.hcl
|-- scripts/deploy.py       SSM-based deploy script (boto3)
|-- .github/workflows/      terraform.yml, deploy.yml
|-- *.tf                    network, security groups, instances, IAM, ECR, key pair, outputs
|-- backend.hcl.example     copy to backend.hcl (git-ignored) and set your state bucket
'-- .terraform.lock.hcl     pinned provider versions (committed on purpose)
4. Prerequisites
AWS account and CLI credentials, Terraform >= 1.7.0, Packer, GitHub CLI (gh), Python 3, and Docker (optional, for local testing).

5. Replicate the setup
Step 1: Create the state backend first
Terraform cannot create the place where it stores its own state. The table name must match providers.tf.

bash
BUCKET=<your-state-bucket>; REGION=us-east-1
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws dynamodb create-table --table-name capstone-cicd-pipeline-tf-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region "$REGION"
Step 2: Configure the backend and build the AMIs
bash
cp backend.hcl.example backend.hcl        # git-ignored; set bucket = "<your-state-bucket>"
terraform init -backend-config=backend.hcl

packer build packer/cicd-server.pkr.hcl   # check each template for required plugins and variables
packer build packer/web-server.pkr.hcl
Then set the two AMI IDs in instances.tf to the images you built. The IDs in this repo belong to another account.

What the images must contain, inferred from the Terraform and deploy code (confirm against your Packer templates): the web image needs nginx, Docker, the AWS CLI and the SSM agent, because instances.tf only writes the nginx site config and the deploy runs aws ecr get-login-password and docker on that instance. The CI/CD image needs Docker, the AWS CLI, Python 3 with boto3 (for scripts/deploy.py), the SSM agent and the GitHub Actions runner files.

Variables: aws_region, project_name and instance_type have defaults. admin_cidr has none, so copy terraform.tfvars.example to terraform.tfvars (git-ignored) and set it. If you change project_name, also update ECR_REPOSITORY and the instance-name filter in .github/workflows/deploy.yml, which hard-code the default names.

Step 3: Pre-flight checks (no AWS calls)
bash
terraform fmt -check -recursive     # exit 0 = formatted (exit 3 = files need formatting)
terraform init -backend=false && terraform validate
validate checks syntax and references only. It does not prove that an AMI or policy will work.

Step 4: Provision
bash
terraform plan -out=tfplan          # read the whole plan
terraform apply tfplan              # applies exactly what you reviewed
CI runs terraform apply -auto-approve without a saved plan (see Known gaps). Locally, use a saved plan.

Step 5: Register the self-hosted runner (manual)
bash
gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token
aws ssm start-session --target <cicd-instance-id>
# on the instance, as the ubuntu user: run config.sh with that token, then svc.sh install
Registration tokens are short-lived. Follow GitHub's runner documentation for the config.sh options.

6. Run the pipeline
Only enable this on a repository you control, with the safeguards below.

Enable Actions for the repository.
Add the AWS credentials the Terraform workflow expects: gh secret set AWS_ACCESS_KEY_ID and gh secret set AWS_SECRET_ACCESS_KEY. Prefer environment secrets, and move to OIDC (see Known gaps).
Create a production environment. Add required reviewers (available on public repos and paid plans) and limit it to main.
Protect main: require a pull request and the plan status check, block force pushes.
Push to main. terraform.yml plans, waits for approval, applies, and deploy.yml builds and deploys.
Verify:
bash
curl -i "http://$(terraform output -raw web_server_public_ip)/"     # expect 200 and the JSON message
aws ssm start-session --target "$(terraform output -raw web_server_instance_id)"     # then: docker ps ; docker logs app
gunicorn needs a few seconds to start. An immediate curl after a deploy can return "connection reset".

Do not attach a self-hosted runner to a public repository that accepts pull requests from forks. deploy.yml triggers only on pushes to main.

7. Production hardening applied
Control	Where
No SSH ingress; admin access via SSM Session Manager	security_groups.tf, iam.tf
IMDSv2 required (http_tokens = "required")	instances.tf
Encrypted root volumes (encrypted = true)	instances.tf
Per-instance IAM roles: ECR push scoped to the app repo, ssm:SendCommand limited by the web server's Name tag, read-only ECR on the web role. The scoped inline policies replaced the broader AmazonSSMFullAccess and AmazonEC2ReadOnlyAccess managed policies	iam.tf
ECR image scan on push; images tagged with the commit SHA	ecr.tf, deploy.yml
Remote state: S3 versioning, default encryption, public access blocked, DynamoDB lock, encrypt = true	providers.tf, Step 1
prevent_destroy on the ECR repository and both IAM roles (force_delete on the ECR repo so an intentional teardown still works)	ecr.tf, iam.tf
Apply runs only on push, after plan, in the production environment, with a concurrency group	terraform.yml
Default workflow token is read-only; markdown-only pushes skip both workflows	repo settings, paths-ignore
The key pair is generated by the tls provider, so the private key is stored in Terraform state. That is why the state bucket is encrypted and access is restricted. The local .pem is git-ignored.

8. Known gaps
 Replace stored IAM keys with OIDC and separate plan and apply roles. Today both jobs use the same repo-level keys.
 terraform apply -auto-approve re-plans instead of applying the reviewed plan. Use a saved plan artifact.
 CI runs plan only. Add fmt -check, validate and app tests.
 The container runs as root and has no HEALTHCHECK.
 Deploys stop the old container before the new one is proven healthy, and Success from SSM only means the commands ran. Add a health check and start-then-switch.
 Rollback is manual: redeploy an earlier image SHA.
 Base image is pinned by minor version only and transitive Python dependencies are not pinned.
 GitHub Actions are pinned by tag, not commit SHA.
 Hard-coded AMI IDs; use variables or a lookup.
 Plain HTTP on port 80 only; add TLS (for example a load balancer with an ACM certificate).
 Both instances sit in a public subnet with unrestricted egress; consider private subnets with VPC endpoints for SSM and ECR.
 The web role's AmazonEC2ContainerRegistryReadOnly policy can read every ECR repository in the account; scope it to the app repository.
9. Roll back and tear down
Roll back (manual; the earlier image must still exist in ECR):

bash
python3 scripts/deploy.py --instance-id "$(terraform output -raw web_server_instance_id)" \
  --image-uri "$(terraform output -raw ecr_repository_url):<previous-sha>" --region us-east-1
Tear down:

bash
# 1. Temporarily remove the prevent_destroy blocks in your working tree. Do not commit this.
terraform plan -destroy
terraform destroy
# 2. Verify against AWS, not just Terraform
aws ec2 describe-instances --region us-east-1 --output table \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,State.Name]'
aws ec2 describe-volumes --region us-east-1 --query 'Volumes[].[VolumeId,State]' --output table
aws ecr describe-repositories --region us-east-1 --query 'repositories[].repositoryName'
# 3. Restore the safety net
git restore <files you edited>
These survive terraform destroy and need deleting separately: the state bucket and lock table, Packer AMIs and their snapshots, and anything a pipeline step created outside Terraform (for example an ECR repository).

Billing is dominated by the two EC2 instances and their public IPv4 addresses. Check current AWS pricing.

10. Approval gates (tested in a sandbox repository)
The gates were proven in a separate public repository, ASulz27/gate-lab, with a dummy plan -> apply -> deploy workflow. The private capstone repo's plan could not enforce them (required reviewers returned a 422, and branch protection showed "Not enforced").

State	Observed result
No protection rule on production	apply and deploy ran straight through
Required reviewer on production	apply paused; deploy waited
Reviewer rejects	apply failed; deploy skipped
Reviewer approves	apply then deploy completed; the comment was recorded
prevent_self_review: true, pusher is the only reviewer	API reported can_approve: false; with it off, true
Limitation: one account played both pusher and reviewer, so this verifies the mechanics, not separation of duties with a second person.

11. Lessons learned
Symptom	Cause and fix
Workflow run fails in 0 s with "workflow file issue"	A job (apply:) sat at column 0. Valid YAML is not a valid workflow. Check the parsed structure, not just syntax.
Pipeline went green but nothing deployed	deploy.py had its __main__ block nested inside the function, an undefined variable, and an unreachable return 0. Found with pyflakes and a mocked-SSM test. Verify outcomes, not just status.
curl right after docker run -d gets "connection reset"	gunicorn is still starting. Wait a few seconds or add a health check.
terraform fmt -check exits 3	Files need formatting (it is not a crash).
Push rejected: "without workflow scope"	gh auth refresh -h github.com -s workflow
Resources survive terraform destroy	They were created outside Terraform (a pipeline-created ECR repo, Packer AMIs). One owner per resource.
12. Verification status
Verified: terraform fmt and validate; the app image builds and serves HTTP 200 locally under gunicorn; deploy.py exit codes against a mocked SSM client; the approval-gate behaviours above; the state backend settings.
Not re-verified end to end since the last teardown: apply, runner registration, the SSM deploy, and the nginx proxy on the instance.
License
See LICENSE.


Claude finished the response
