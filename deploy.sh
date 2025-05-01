#!/usr/bin/env bash
set -euo pipefail

# where all your CFN templates now live:
TEMPLATES_DIR=templates/core

echo "Skipping legacy OpenSearch CFN (using existing domain 'photos')"

echo "1) Deploy S3 buckets…"
S3_CF="$TEMPLATES_DIR/s3-buckets.yaml"
if [ ! -f "$S3_CF" ]; then
  echo "❌ Cannot find $S3_CF" >&2
  exit 1
fi
aws cloudformation deploy \
  --stack-name cfn-photoalbum-s3 \
  --template-file "$S3_CF" \
  --capabilities CAPABILITY_NAMED_IAM
echo "✅ S3 buckets deployed"

echo "2) Deploy parameters…"
PARAM_CF="$TEMPLATES_DIR/parameters.yaml"
if [ ! -f "$PARAM_CF" ]; then
  echo "❌ Cannot find $PARAM_CF" >&2
  exit 1
fi
aws cloudformation deploy \
  --stack-name cfn-photoalbum-parameters \
  --template-file "$PARAM_CF" \
  --capabilities CAPABILITY_NAMED_IAM
echo "✅ Parameters deployed"

echo "3) Deploy IAM roles…"
ES_ARN=$(aws cloudformation list-exports \
  --query "Exports[?Name=='cfn-PhotoAlbum-ESDomainArn'].Value" --output text)
IAM_CF="$TEMPLATES_DIR/iam-roles.yaml"
if [ ! -f "$IAM_CF" ]; then
  echo "❌ Cannot find $IAM_CF" >&2
  exit 1
fi
aws cloudformation deploy \
  --stack-name cfn-photoalbum-iam \
  --template-file "$IAM_CF" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides cfnESDomainArn="$ES_ARN"
echo "✅ IAM roles deployed"

echo "4) Deploy Lambda functions…"
ES_ENDPOINT=$(aws cloudformation list-exports \
  --query "Exports[?Name=='cfn-PhotoAlbum-ESDomainEndpoint'].Value" --output text)
INDEX_ROLE_ARN=$(aws cloudformation list-exports \
  --query "Exports[?Name=='cfn-PhotoAlbum-IndexLambdaRoleArn'].Value" --output text)
SEARCH_ROLE_ARN=$(aws cloudformation list-exports \
  --query "Exports[?Name=='cfn-PhotoAlbum-SearchLambdaRoleArn'].Value" --output text)
LAMBDA_CF="$TEMPLATES_DIR/lambda-functions.yaml"
if [ ! -f "$LAMBDA_CF" ]; then
  echo "❌ Cannot find $LAMBDA_CF" >&2
  exit 1
fi
aws cloudformation deploy \
  --stack-name cfn-photoalbum-functions \
  --template-file "$LAMBDA_CF" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      ESDomainEndpoint="$ES_ENDPOINT" \
      IndexLambdaRoleArn="$INDEX_ROLE_ARN" \
      SearchLambdaRoleArn="$SEARCH_ROLE_ARN"
echo "✅ Lambda functions deployed"

echo "5) Deploy API Gateway…"
PHOTO_BUCKET=$(aws cloudformation list-exports \
  --query "Exports[?Name=='cfn-PhotoAlbum-PhotoBucketName'].Value" \
  --output text)
API_GATEWAY_ROLE_ARN=$(aws cloudformation list-exports \
  --query "Exports[?Name=='cfn-PhotoAlbum-ApiGatewayS3RoleArn'].Value" \
  --output text)
SEARCH_FN_ARN=$(aws cloudformation list-exports \
  --query "Exports[?Name=='cfn-PhotoAlbum-SearchFunctionArn'].Value" \
  --output text)
API_CF="$TEMPLATES_DIR/api-gateway.yaml"
if [ ! -f "$API_CF" ]; then
  echo "❌ Cannot find $API_CF" >&2
  exit 1
fi

aws cloudformation deploy \
  --stack-name cfn-photoalbum-api \
  --template-file "$API_CF" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      PhotoBucketName="$PHOTO_BUCKET" \
      ApiGatewayS3RoleArn="$API_GATEWAY_ROLE_ARN" \
      SearchFunctionArn="$SEARCH_FN_ARN"
echo "✅ API Gateway deployed"


# ─── Show final endpoints ──────────────────────────────────────────────
PHOTO_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-s3 \
  --query 'Stacks[0].Outputs[?OutputKey==`cfnPhotoBucketName`].OutputValue' \
  --output text)
FRONTEND_URL=$(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-s3 \
  --query 'Stacks[0].Outputs[?OutputKey==`cfnFrontendWebsiteURL`].OutputValue' \
  --output text)
API_URL=$(aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-api \
  --query 'Stacks[0].Outputs[?OutputKey==`cfnApiUrl`].OutputValue' \
  --output text)

echo
echo "Photo bucket:  ${PHOTO_BUCKET}"
echo "Frontend URL:  ${FRONTEND_URL}"
echo "API URL:  "
aws cloudformation describe-stacks \
  --stack-name cfn-photoalbum-api \
  --query "Stacks[0].Outputs[?OutputKey=='cfnApiUrl'].OutputValue" \
  --output text