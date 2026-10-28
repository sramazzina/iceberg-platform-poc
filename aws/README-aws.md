# AWS resources for the lab

The scripts in this folder create and remove the AWS resources of the lab.
Run them with administrative AWS credentials, for example in AWS CloudShell.
Do not run them on the lab VM: the VM role cannot create IAM roles.

## VM sizing

| Item | Recommendation |
|---|---|
| Instance type | 4 vCPU and 16 GB RAM minimum, for example `m6i.xlarge` or `t3.xlarge` |
| Disk | 50 GB gp3 |
| Operating system | Ubuntu Server 24.04 LTS |
| Network | Security group: inbound TCP 22 from your IP only. With SSM: no inbound port |
| IAM | An instance profile with a role. `setup.sh` adds the lab policy to this role |

## Software on the VM

1. Install Docker Engine and the Compose plugin from the Docker apt repository:
   <https://docs.docker.com/engine/install/ubuntu/>
2. Add your user to the `docker` group: `sudo usermod -aG docker $USER`. Log out and in again.
3. Install the AWS CLI v2: <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html>
4. Check: `docker compose version` and `aws --version`.

## What `setup.sh` creates

| Resource | Detail |
|---|---|
| S3 bucket `${S3_BUCKET}` | Block Public Access on, default encryption SSE-S3 |
| Inline policy `iceberg-lab-vm` on the VM role | S3 read/write on `nessie/` and `rest/`, list on `polaris/`, `sts:AssumeRole` on `polaris-s3-access` |
| IAM role `polaris-s3-access` | Trusted by the VM role with an external ID. S3 read/write on `polaris/` only |
| VM metadata options | IMDSv2 required, `HttpPutResponseHopLimit=2` |

The hop limit must be 2: containers on a Docker bridge network are one extra network hop
from the instance metadata service. With hop limit 1 they do not receive IMDSv2 tokens, so
they get no credentials. Source:
<https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html>

## Run `setup.sh`

1. Open AWS CloudShell in the region of the VM.
2. Clone the repository: `git clone https://github.com/sramazzina/iceberg-platform-poc.git`
3. Go to the folder: `cd iceberg-platform-poc`
4. Set the parameters:
   ```bash
   export AWS_REGION=<region of the VM>
   export S3_BUCKET=<globally unique bucket name>
   export INSTANCE_ID=<id of the lab VM>
   ```
   Set `AWS_REGION` explicitly to the region of the VM. CloudShell sets `AWS_REGION` to the console region, which can be a different region.
5. Run the script: `aws/setup.sh`
6. Copy the four lines printed at the end into `.env` on the VM.

The script is idempotent. Run it again after a change: it keeps the bucket, the role and the
external ID.

## Check from the VM

Run on the VM.

The AWS CLI on the VM must use the instance profile. If your shell sets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` or `AWS_PROFILE`, the CLI uses these values instead. Unset them before you run the check:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
```

Then run the check:

```bash
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/
aws s3 ls "s3://$S3_BUCKET/"
```

The second command prints the VM role name. The third command succeeds (the bucket is empty at first).

## Run `teardown.sh`

1. Stop the lab on the VM: `make down`.
2. In CloudShell, set `AWS_REGION`, `S3_BUCKET`, `INSTANCE_ID` as for `setup.sh`.
3. Run the script: `aws/teardown.sh`
4. Type the bucket name when the script asks for it. Any other answer keeps the bucket.

If the VM is already terminated, the script cannot find the VM role. It then deletes the other resources and tells you to remove the inline policy `iceberg-lab-vm` by hand, if the role still exists.

The script does not delete the VM role and does not change the hop limit, because `setup.sh`
did not create them.

## Costs

- The VM costs money while it runs. Stop it when you do not use the lab.
- An EBS volume costs money while it exists, also when the VM is stopped.
- S3 storage and requests cost money. `teardown.sh` deletes the bucket.
- IAM roles and policies are free.
