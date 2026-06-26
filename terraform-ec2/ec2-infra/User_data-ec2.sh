#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# --- Configuration Variables ---
AWS_REGION="us-east-1"
ECR_REGISTRY="<YOUR_AWS_ACCOUNT_ID>.dkr.ecr.<YOUR_AWS_REGION>.amazonaws.com"
# -------------------------------

install_docker(){
    echo "Removing old Docker versions (if any)..."
    sudo apt remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true
    sudo apt autoremove -y || true

    echo "Updating system..."
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg git unzip

    echo "Creating keyring..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo rm -f /etc/apt/keyrings/docker.gpg
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "Installing Docker..."
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "Enabling Docker..."
    sudo systemctl enable docker
    sudo systemctl start docker

    echo "Adding user to docker group..."
    sudo usermod -aG docker ubuntu
}

install_aws_cli(){
    echo "Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
}

deploy_project(){
    echo "Setting up project directory..."
    mkdir -p /home/ubuntu/<YOUR_PROJECT_NAME>
    cd /home/ubuntu/<YOUR_PROJECT_NAME>

    # 1. Download the docker-compose.yml
    curl -L -o docker-compose.yml https://raw.githubusercontent.com/<YOUR_ORG>/<YOUR_REPO>/refs/heads/main/docker-compose.yml

    # 2. Authenticate with ECR (Relies on IAM Instance Profile attached by Terraform)
    echo "Logging into AWS ECR..."
    aws ecr get-login-password --region $AWS_REGION | sudo docker login --username AWS --password-stdin $ECR_REGISTRY

    # 3. Pull the image from ECR and start the containers
    echo "Pulling images and starting environment..."
    sudo docker compose pull
    sudo docker compose up -d
}

# Run the execution
install_docker
install_aws_cli
deploy_project

# Force SSH to cycle so your terminal session immediately recognizes the group change
sudo systemctl restart ssh