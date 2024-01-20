#!/bin/bash

export stack_name="${1:-SparkOnEKS}"
export region="${2:-us-east-1}"

echo "================================================================================================="
echo "  Make sure your CloudFormation stack name $stack_name is correct and exists in region: $region  "
echo "  If you use a different name, rerun the script with parameters:"
echo "      ./deployment/post-deployment.sh <stack_name> <region>"
echo "================================================================================================="

# 1. update ECR endpoint in example jobs
export ECR_IMAGE_URI=$(aws cloudformation describe-stacks --stack-name $stack_name --region $region \
--query "Stacks[0].Outputs[?OutputKey=='IMAGEURI'].OutputValue" --output text)
echo "Updated ECR endpoint in sample job files in source/example/"
sed -i.bak "s|{{ECR_URL}}|${ECR_IMAGE_URI}|g" source/example/*.yaml

find . -type f -name "*.bak" -delete

# 2. install k8s command tools 
echo "================================================================================"
echo "  Installing kubectl tool on macOS ..."
echo "  For other operationing system, install the kubectl > 1.27 here:"
echo "  https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html"
echo "================================================================================"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
chmod +x kubectl
mkdir -p $HOME/bin && mv kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
echo "Installed kubectl version: "
kubectl version --client
echo "================================================================================================"
echo " Installing argoCLI tool on Mac ..."
echo " Check out https://github.com/argoproj/argo-workflows/releases for other OS type installation."
echo "================================================================================================"
VERSION=v3.0.2
sudo curl -sLO https://github.com/argoproj/argo-workflows/releases/download/${VERSION}/argo-darwin-amd64.gz && gunzip argo-darwin-amd64.gz
chmod +x argo-darwin-amd64 && sudo mv ./argo-darwin-amd64 /usr/local/bin/argo
echo "Installed argoCLI version: "
argo version --short

# 3. connect to the EKS newly created
echo `aws cloudformation describe-stacks --stack-name $stack_name --region $region --query "Stacks[0].Outputs[?starts_with(OutputKey,'eksclusterEKSConfig')].OutputValue" --output text` | bash
echo "Testing EKS connection..."
kubectl get svc

# 4. get Jupyter Hub login
LOGIN_URI=$(aws cloudformation describe-stacks --stack-name $stack_name --region $region \
--query "Stacks[0].Outputs[?OutputKey=='JUPYTERURL'].OutputValue" --output text)
SEC_ID=$(aws secretsmanager list-secrets --query "SecretList[?not_null(Tags[?Value=='$stack_name'])].Name" --output text)
LOGIN=$(aws secretsmanager get-secret-value --secret-id $SEC_ID --query SecretString --output text)
echo -e "\n=============================== JupyterHub Login =============================================="
echo -e "\nJUPYTER_URL: $LOGIN_URI"
echo "LOGIN: $LOGIN" 
echo "================================================================================================"

