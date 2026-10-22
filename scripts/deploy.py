#!/usr/bin/env python3
"""
Deploys a new Docker image to the web server via AWS SSM — no SSH, no stored
credentials. Replaces the "Pull docker image" step Jenkins performed in the
original architecture.
"""
import argparse
import sys
import time

import boto3

def deploy(instance_id: str, image_uri: str, region: str) -> int:
    ssm = boto3.client("ssm", region_name=region)
    
    commands = [
        f"aws ecr get-login-password --region {region} "
        f"| docker login --username AWS --password-stdin "
        f"{image_uri.split('/')[0]}",
        f"docker pull {image_uri}",
        "docker stop app || true",
        "docker rm app || true",
        f"docker run -d --name app --restart unless-stopped "
        f"-p 5000:5000 {image_uri}",
    ]

    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": commands},
        TimeoutSeconds=120,
    )
    command_id = response["Command"]["CommandId"]

    for _ in range(30):
        time.sleep(5)
        result = ssm.get_command_invocation(
            CommandId=command_id, InstanceId=instance_id
        )
        if result["Status"] in ("Success", "Failed", "Cancelled", "TimedOut"):
            break

    print(f"SSM command status: {result['Status']}")
    print(result.get("StandardOutputContent", ""))
    if result["Status"] != "Success":
        print(result.get("StandardErrorContent", ""), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--instance-id", required=True)
    parser.add_argument("--image-uri", required=True)
    parser.add_argument("--region", default="us-east-1")
    args = parser.parse_args()

    sys.exit(deploy(args.instance_id, args.image_uri, args.region))