# Terraform EC2 + S3 Web Application

## Quick Start

### Prerequisites
- AWS CLI configured (`aws configure`)
- Terraform installed
- AWS IAM permissions for EC2, S3, IAM, VPC

### Deployment Steps

1. **Edit variables.tf**
   - Change `content_bucket_name` to a globally unique name
   
2. **Initialize Terraform**
   ```bash
   terraform init
   ```

3. **Review the plan**
   ```bash
   terraform plan
   ```

4. **Deploy**
   ```bash
   terraform apply
   ```
   Type `yes` when prompted.

5. **Wait 3-5 minutes** for the EC2 instance to install Node.js and start the application.

6. **Access your website**
   Terraform will output the URL:
   ```
   website_url = "http://54.123.45.67"
   ```

## Architecture

```
Internet → Security Group → EC2 Instance (Node.js) → IAM Role → S3 Bucket
```

## What Gets Deployed

- **EC2 Instance** (t2.micro) - Runs Node.js web server
- **S3 Bucket** - Stores content files
- **IAM Role + Policy** - Allows EC2 to access S3 securely
- **Security Group** - HTTP (80), HTTPS (443), SSH (22)
- **Auto-start Service** - Webapp starts automatically on boot

## Updating S3 Content

To update the message or config without redeploying EC2:

1. Edit the content in `main.tf`
2. Run: `terraform apply -target=aws_s3_object.message`
3. Refresh your browser

## Estimated Cost

- **EC2 t2.micro**: ~$8.50/month (FREE with AWS Free Tier for 12 months)
- **S3 Storage**: ~$0.023/GB/month (negligible for small files)
- **Total**: ~$8-10/month (or FREE with Free Tier)

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

## Troubleshooting

### Application not loading?
- Wait 3-5 minutes after `terraform apply` completes
- Check EC2 instance is running in AWS Console
- Verify security group allows port 80

### SSH into instance (if needed)
1. Create/use EC2 key pair
2. Add `key_name = "your-key"` to aws_instance resource
3. `ssh -i your-key.pem ec2-user@<public-ip>`

### Check application logs
```bash
sudo journalctl -u webapp -f
```

## Project Files

- `main.tf` - Main infrastructure configuration
- `variables.tf` - Input variables
- `outputs.tf` - Output values after deployment
- `terraform.tfvars` - Variable values (EDIT THIS)
- `user-data.sh` - EC2 bootstrap script
- `README.md` - This file

## Security Notes

**For Production:**
- Restrict `ssh_cidr_blocks` to your IP only
- Use HTTPS with ACM certificate + ALB
- Deploy in private subnet with NAT Gateway
- Enable S3 bucket versioning
- Add CloudWatch monitoring

## Learn More

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
