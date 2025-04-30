set -euo pipefail

aws cloudformation deploy \
  --template-file templates/s3-buckets.yaml \
  --stack-name photoalbum-s3

aws cloudformation deploy \
  --template-file templates/iam-roles.yaml \
  --stack-name photoalbum-iam \
  --capabilities CAPABILITY_IAM

aws cloudformation deploy \
  --template-file templates/lambda-functions.yaml \
  --stack-name photoalbum-lambda \
  --capabilities CAPABILITY_IAM

aws cloudformation deploy \
  --template-file templates/api-gateway.yaml \
  --stack-name photoalbum-api \
  --capabilities CAPABILITY_IAM

echo "Frontend site URL:"
aws cloudformation describe-stacks --stack-name photoalbum-s3 \
  --query 'Stacks[0].Outputs[?OutputKey==`FrontendWebsiteURL`].OutputValue' \
  --output text

echo "API endpoint URL:"
aws cloudformation describe-stacks --stack-name photoalbum-api \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
  --output text
