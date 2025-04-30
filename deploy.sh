set -euo pipefail

echo "1) Deploying OpenSearch domain…"
aws cloudformation deploy \
  --template-file templates/opensearch-domain.yaml \
  --stack-name cfn-photoalbum-opensearch \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides MasterUserPassword=Test1234!

echo "OpenSearch ready"

echo "2) Deploying S3 buckets with cfn- prefix…"
aws cloudformation deploy \
  --template-file templates/s3-buckets.yaml \
  --stack-name cfn-photoalbum-s3 \
  --parameter-overrides \
    PhotoBucketSuffix=my-photo-bucket-hw3 \
    FrontendBucketSuffix=my-frontend-bucket-hw3

echo "S3 buckets created"

echo "3) Deploying IAM roles…"
ES_DOMAIN_ARN=$(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-opensearch \
  --query 'Stacks[0].Outputs[?OutputKey==`cfn-ESDomainArn`].OutputValue' \
  --output text)

aws cloudformation deploy \
  --template-file templates/iam-roles.yaml \
  --stack-name cfn-photoalbum-iam \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides cfn-ESDomainArn="${ES_DOMAIN_ARN}"

echo "IAM roles ready"

echo "4) Deploying Lambda functions…"
ES_DOMAIN_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-opensearch \
  --query 'Stacks[0].Outputs[?OutputKey==`cfn-ESDomainEndpoint`].OutputValue' \
  --output text)

aws cloudformation deploy \
  --template-file templates/lambda-functions.yaml \
  --stack-name cfn-photoalbum-lambda \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ESDomainEndpoint="${ES_DOMAIN_ENDPOINT}"

echo "Lambdas deployed"

echo "5) Deploying API Gateway…"
aws cloudformation deploy \
  --template-file templates/api-gateway.yaml \
  --stack-name cfn-photoalbum-api \
  --capabilities CAPABILITY_NAMED_IAM

echo "API Gateway deployed"

echo "6) Deploying Lambda invoke permissions…"
API_ID=$(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-api \
  --query 'Stacks[0].Outputs[?OutputKey==`cfn-ApiId`].OutputValue' \
  --output text)

aws cloudformation deploy \
  --template-file templates/triggers.yaml \
  --stack-name cfn-photoalbum-triggers \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides cfn-ApiId="${API_ID}"

echo "Permissions wired up"

echo
echo "Photo bucket name: $(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-s3 \
  --query 'Stacks[0].Outputs[?OutputKey==`cfn-PhotoBucketName`].OutputValue' \
  --output text)"
echo "Frontend URL:      $(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-s3 \
  --query 'Stacks[0].Outputs[?OutputKey==`cfn-FrontendWebsiteURL`].OutputValue' \
  --output text)"
echo "API URL:           $(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-api \
  --query 'Stacks[0].Outputs[?OutputKey==`cfn-ApiUrl`].OutputValue' \
  --output text)"
