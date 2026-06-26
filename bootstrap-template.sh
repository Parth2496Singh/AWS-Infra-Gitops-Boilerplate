#!/bin/bash
# ==============================================================================
# AWS EKS GitOps Boilerplate - Template Bootstrapper
# ==============================================================================
# This script injects your custom environment variables into the boilerplate code.
# 
# 1. EDIT the variables below to match your AWS environment and GitHub details.
# 2. RUN the script: `./bootstrap-template.sh`
# ==============================================================================

# --- EDIT THESE VARIABLES ---
export PROJECT_NAME="my-awesome-app"
export AWS_ACCOUNT_ID="123456789012"
export AWS_REGION="us-east-1" 
export GITHUB_ORG="my-org" #Github Username
export GITHUB_REPO="my-repo" #Repo Name
export EMAIL="admin@example.com"
export MY_NAME="Jane Doe"
# -----------------------------

echo "🚀 Bootstrapping Template with your variables..."

# Detect OS for sed inline replacement compatibility (Linux vs macOS)
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}
export -f sedi

# Function to run bulk replace
bulk_replace() {
  local search=$1
  local replace=$2
  
  # Find all files excluding .git, .terraform directories, and this script itself
  find . -type f -not -path "*/\.git/*" -not -path "*/\.terraform/*" -not -name "bootstrap-template.sh" -exec bash -c 'sedi "s|$1|$2|g" "$0"' {} "$search" "$replace" \;
}

bulk_replace "<YOUR_PROJECT_NAME>" "$PROJECT_NAME"
bulk_replace "<YOUR_AWS_ACCOUNT_ID>" "$AWS_ACCOUNT_ID"
bulk_replace "<YOUR_AWS_REGION>" "$AWS_REGION"
bulk_replace "<YOUR_ORG>" "$GITHUB_ORG"
bulk_replace "<YOUR_REPO>" "$GITHUB_REPO"
bulk_replace "<YOUR_EMAIL>" "$EMAIL"
bulk_replace "<YOUR_NAME>" "$MY_NAME"

echo "✅ Variables injected successfully!"
echo "⚠️  Next Steps: Ensure you manually rename the Terraform state buckets in 'remote-backend/main.tf' and 'terraform.tf' files if you haven't already."
