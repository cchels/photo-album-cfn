set -euo pipefail

echo "Deploying parameters (no stack, just used for guidance)"

echo "Deploying S3 buckets..."
aws cloudformation deploy \
  --template-file templates/s3-buckets.yaml \
  --stack-name photoalbum-s3

echo "Deploying IAM roles..."
aws cloudformation deploy \
  --template-file templates/iam-roles.yaml \
  --stack-name photoalbum-iam \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ESDomainArn="arn:aws:es:us-east-1:825765411228:domain/photos/*"

echo "Deploying Lambda functions..."
aws cloudformation deploy \
  --template-file templates/lambda-functions.yaml \
  --stack-name photoalbum-lambda \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ESDomainEndpoint="https://search-photos-2kdopq4li5ts2w6mcaqobflreu.us-east-1.es.amazonaws.com"

echo "Deploying API Gateway..."
aws cloudformation deploy \
  --template-file templates/api-gateway.yaml \
  --stack-name photoalbum-api \
  --capabilities CAPABILITY_NAMED_IAM

echo "Deploying Lambda invoke permissions..."
aws cloudformation deploy \
  --template-file templates/triggers.yaml \
  --stack-name photoalbum-triggers \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ApiId="$(aws cloudformation describe-stacks --stack-name photoalbum-api --query 'Stacks[0].Outputs[?OutputKey==\`ApiId\`].OutputValue' --output text)"

echo ""
echo "Frontend website: $(aws cloudformation describe-stacks --stack-name photoalbum-s3 --query 'Stacks[0].Outputs[?OutputKey==\`FrontendWebsiteURL\`].OutputValue' --output text)"
echo "API base URL:    $(aws cloudformation describe-stacks --stack-name photoalbum-api --query 'Stacks[0].Outputs[?OutputKey==\`ApiUrl\`].OutputValue' --output text)"
