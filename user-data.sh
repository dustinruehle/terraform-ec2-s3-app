#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting EC2 initialization ==="

# ---- System Prep ----
yum update -y
yum install -y git python3 python3-pip awscli jq

# ---- Install Node.js for existing web app ----
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# ---- Setup Web App ----
mkdir -p /opt/webapp
cd /opt/webapp

# Create Node.js app (placeholder; replace with your original app content)
cat > server.js <<'EOFSERVER'
const http = require('http');
const PORT = 80;
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end('EC2 Web App is running.\n');
});
server.listen(PORT, () => console.log('Server running on port ' + PORT));
EOFSERVER

cat > package.json <<'EOFPACKAGE'
{
  "name": "ec2-s3-webapp",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {"start": "node server.js"}
}
EOFPACKAGE

npm install

cat > /etc/systemd/system/webapp.service <<EOFSERVICE
[Unit]
Description=EC2 Web Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/webapp
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSERVICE

systemctl daemon-reload
systemctl enable webapp
systemctl start webapp

# ---- Setup Temporal Python Worker ----
echo "=== Setting up Temporal Order Management Worker ==="

mkdir -p /opt/temporal-order-worker/certs
cd /opt/temporal-order-worker

# Install Python dependencies
pip3 install temporalio boto3

# --- Pull Temporal Cloud credentials from AWS Secrets Manager ---
SECRET_NAME="temporal-cloud-credentials"
AWS_REGION="$(curl -s http://169.254.169.254/latest/meta-data/placement/region)"

echo "Fetching Temporal Cloud credentials from Secrets Manager: $SECRET_NAME"

aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$AWS_REGION" \
  --query SecretString \
  --output text > secret.json

# Extract values
NAMESPACE=$(jq -r '.namespace' secret.json)
ADDRESS=$(jq -r '.address' secret.json)
CERT=$(jq -r '.cert' secret.json)
KEY=$(jq -r '.key' secret.json)

# Write certs to disk
echo "$CERT" | base64 -d > /opt/temporal-order-worker/certs/client.pem
echo "$KEY" | base64 -d > /opt/temporal-order-worker/certs/client.key

# Cleanup
rm -f secret.json

# --- Create environment file ---
cat > /opt/temporal-order-worker/worker.env <<EOF
TEMPORAL_NAMESPACE=$NAMESPACE
TEMPORAL_ADDRESS=$ADDRESS
TEMPORAL_MTLS_CERT_PATH=/opt/temporal-order-worker/certs/client.pem
TEMPORAL_MTLS_KEY_PATH=/opt/temporal-order-worker/certs/client.key
EOF

# --- Create minimal worker.py example (replace with your demo’s code) ---
cat > /opt/temporal-order-worker/worker.py <<'EOF'
import asyncio, os
from temporalio.client import Client
from temporalio.worker import Worker
from order_workflows import *  # replace with your demo imports

async def main():
    client = await Client.connect(
        os.getenv("TEMPORAL_ADDRESS"),
        namespace=os.getenv("TEMPORAL_NAMESPACE"),
        tls=Client.TLSConfig(
            client_cert_path=os.getenv("TEMPORAL_MTLS_CERT_PATH"),
            client_private_key_path=os.getenv("TEMPORAL_MTLS_KEY_PATH"),
        ),
    )
    worker = Worker(
        client,
        task_queue="order-task-queue",
        workflows=[OrderWorkflow],
        activities=[charge_customer, update_inventory, send_confirmation],
    )
    print("Python Temporal worker started and connected to Temporal Cloud.")
    await worker.run()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# --- Create systemd service for the Temporal worker ---
cat > /etc/systemd/system/temporal-worker.service <<EOF
[Unit]
Description=Temporal Order Management Python Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/temporal-order-worker
EnvironmentFile=/opt/temporal-order-worker/worker.env
ExecStart=/usr/bin/python3 /opt/temporal-order-worker/worker.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable temporal-worker
systemctl start temporal-worker

echo "=== Initialization complete! ==="
echo "Node.js app on port 80 and Temporal worker connected to Temporal Cloud."