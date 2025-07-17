# Jenkins AWS Deployment with Terraform

This Terraform project deploys a Jenkins instance in a private subnet within an AWS VPC, along with a bastion host in a public subnet for secure access.

It is meant to be used to facilitate testing secure delivery of GitHub webhooks to a private network to trigger builds in Jenkins.  For example, it could be used in tandem with the aws-api-gateway-forwarder code in this repo.  Note this is not a production ready setup.  It is only meant to be used for testing.  For instance, it is using an agent running on the Jenkins host instead of a separate agent machine.

## Architecture

- VPC with 2 public and 2 private subnets across 2 availability zones
- Internet Gateway for public internet access
- NAT Gateway for private subnet internet access
- Bastion host in a public subnet
- Jenkins instance in a private subnet
- Security groups for bastion and Jenkins instances

## Prerequisites

1. AWS account and configured AWS CLI
2. Terraform installed (version 0.12+)
3. EC2 key pair created in the target AWS region

## Usage

1. Clone this repository
2. Navigate to the project directory
3. Initialize Terraform:

   ```bash
   terraform init
   ```

4. Review and modify the `variables.tf` file if needed
5. Create a `terraform.tfvars` file with your specific values:

   ```bash
   aws_region = "us-east-1"
   key_name   = "your-ec2-key-pair-name"
   ```

6. Plan the deployment:

   ```bash
   terraform plan
   ```

7. Apply the changes:

   ```bash
   terraform apply
   ```

## Accessing Jenkins

0. Get the bastion public IP and Jenkins private IP from the output of the terraform apply step

   ```bash
   terraform output
   ```

1. SSH into the bastion host (passing the SSH agent so you don't need to add the Jenkins private key to the ssh-agent):

   ```bash
   ssh -A -i /path/to/your/key.pem ec2-user@<bastion-public-ip>
   ```

2. From the bastion, SSH into the Jenkins instance:

   ```bash
   ssh -i /path/to/your/key.pem ec2-user@<jenkins-private-ip>
   ```

3. Get the initial Jenkins admin password:

   ```bash
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```

4. Access Jenkins web interface through a browser by SSH port forwarding:

   ```bash
   ssh -i /path/to/your/key.pem -L 8080:<jenkins-private-ip>:8080 ec2-user@<bastion-public-ip>
   http://localhost:8080
   ```

Note when prompted for the initial Jenkins admin password, use the password you got in step 3.  Then select "Install suggested plugins".  After that you will be prompted to create a new admin user.  Finally set the URL to `http://localhost:8080/`.  Click Save and Finish.  Then click Start using Jenkins.
   Note I tried `http://<jenkins-private-ip>:8080/` and there was some weird slowness...  May or may not have been related...

## GitHub Webhook Testing

Create a GitHub repo with a sample application and Jenkinsfile.  See the sample-python-app in this repo for an example, but feel free to create your own.  Note the Jenkins host needs to have the pre-requisites to handle the build steps.  I recommend using a public repo for this testing so you don't need Jenkins to auth to pull your code.  If you prefer private, you will need to go to "Manage Jenkins" -> "Manage Credentials" and add your GitHub credentials so Jenkins can access your private repo.  You may also need to update the sample Jenkinsfile to use your credentials.

In Jenkins, create a new pipeline job as follows:

- Go to Jenkins dashboard and click "New Item"
- Enter a name (like sample-python-app) for your job, select "Pipeline", and click OK
- In the Pipeline section, choose "Pipeline script from SCM"
- Select Git as the SCM
- Enter your GitHub repository URL (use HTTPS for public repos: https://github.com/your-org/sample-python-app)
  - If you need credentials select them here.  But for public, None is the correct choice.
- Set the branch to `*/main` (or your default branch)
- Save the job

Now trigger a build manually (Click Build Now) to see if it works.

Next setup your webhook forwarder.  Check out aws-api-gateway-forwarder in this repo for a walkthrough.  This will need to point to your Jenkins URL.  For example: `http://<jenkins-private-ip>:8080/github-webhook/`

Finally in your Jenkins pipeline job configuration, go to your "Build Triggers" section and check "GitHub hook trigger for GITScm polling" and save the job configuration.

Now you can test.  When you push an update to your GitHub repo, it should trigger a build in Jenkins.

There you have it.  A secure setup for delivering webhooks from GitHub to a private Jenkins server!

## Clean Up

To destroy all created resources:

```bash
terraform destroy
```

## Security Considerations

- The bastion host is the only entry point to the Jenkins instance
- Jenkins is deployed in a private subnet for enhanced security
- Security groups restrict access to necessary ports only
- Remember to keep your EC2 key pair secure and never commit it to version control

## Customization

You can customize the deployment by modifying the `variables.tf` file or providing different values in `terraform.tfvars`.

## Cost

An estimate of the cost of deploying this configuration in AWS:

| Resource | Cost |
| -------- | -------- |
| EC2 Bastion host: t3a.nano | $0.0047 per hour ≈ $3.47 per month |
| EC2 Jenkins instance: t3a.small | $0.0188 per hour ≈ $13.91 per month |
| NAT Gateway | $0.045 per hour ≈ $32.85 per month |
| Elastic IP | Free while attached to a running instance |
| Data transfer out | $0.09 per GB (first 10 TB) |
| Data transfer between AZs | $0.01 per GB |

Total estimated cost per month (assuming 100GB out and 50GB between AZs):
$3.47 + $13.91 + $32.85 + $9 + $0.50 ≈ $59.73
