#!/usr/bin/env bash
set -euo pipefail

echo "1) Deploy OpenSearch domain…"
aws cloudformation deploy \
  --template-file templates/opensearch-domain.yaml \
  --stack-name cfn-photoalbum-opensearch \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides MasterUserPassword=Test1234!

echo "✅ OpenSearch ready"

echo "2) Deploy S3 buckets with cfn- prefix…"
aws cloudformation deploy \
  --template-file templates/s3-buckets.yaml \
  --stack-name cfn-photoalbum-s3 \
  --parameter-overrides \
      PhotoBucketSuffix=my-photo-bucket-hw3 \
      FrontendBucketSuffix=my-frontend-bucket-hw3

echo "✅ S3 buckets ready"

echo "3) Deploy IAM roles…"
ES_ARN=$(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-opensearch \
  --query 'Stacks[0].Outputs[?OutputKey==`cfnESDomainArn`].OutputValue' \
  --output text)

aws cloudformation deploy \
  --template-file templates/iam-roles.yaml \
  --stack-name cfn-photoalbum-iam \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides cfnESDomainArn="${ES_ARN}"

echo "✅ IAM roles ready"

echo "4) Deploy Lambda functions…"
ES_EP=$(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-opensearch \
  --query 'Stacks[0].Outputs[?OutputKey==`cfnESDomainEndpoint`].OutputValue' \
  --output text)

aws cloudformation deploy \
  --template-file templates/lambda-functions.yaml \
  --stack-name cfn-photoalbum-lambda \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ESDomainEndpoint="${ES_EP}"

echo "✅ Lambdas deployed"

echo "5) Deploy API Gateway…"
aws cloudformation deploy \
  --template-file templates/api-gateway.yaml \
  --stack-name cfn-photoalbum-api \
  --capabilities CAPABILITY_NAMED_IAM

echo "✅ API Gateway deployed"

echo "6) Deploy Lambda permissions…"
API_ID=$(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-api \
  --query 'Stacks[0].Outputs[?OutputKey==`cfnApiId`].OutputValue' \
  --output text)

aws cloudformation deploy \
  --template-file templates/triggers.yaml \
  --stack-name cfn-photoalbum-triggers \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides cfnApiId="${API_ID}"

echo
echo "Frontend URL: $(aws cloudformation describe-stacks --stack-name cfn-photoalbum-s3 \
  --query 'Stacks[0].Outputs[?OutputKey==`cfnFrontendWebsiteURL`].OutputValue' --output text)"
echo "API URL:      $(aws cloudformation describe-stacks --stack-name cfn-photoalbum-api \
  --query 'Stacks[0].Outputs[?OutputKey==`cfnApiUrl`].OutputValue' --output text)"
