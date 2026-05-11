#!/bin/bash
# Phase 1 — DynamoDB Global Tables
source scripts/00-setup.sh

echo "Creating DynamoDB table in $AWS_REGION..."
aws dynamodb create-table \
  --table-name "$APP_NAME-sessions" \
  --attribute-definitions AttributeName=sessionId,AttributeType=S \
  --key-schema AttributeName=sessionId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION

echo "Waiting for table to be active..."
aws dynamodb wait table-exists \
  --table-name "$APP_NAME-sessions" \
  --region $AWS_REGION
echo "Table active in $AWS_REGION"

echo "Adding replica in $DR_REGION..."
aws dynamodb update-table \
  --table-name "$APP_NAME-sessions" \
  --replica-updates "[{\"Create\":{\"RegionName\":\"$DR_REGION\"}}]" \
  --region $AWS_REGION

echo "Waiting 30s for replication to initialise..."
sleep 30

echo "Verifying replicas..."
aws dynamodb describe-table \
  --table-name "$APP_NAME-sessions" \
  --region $AWS_REGION \
  --query 'Table.Replicas[].{Region:RegionName,Status:ReplicaStatus}' \
  --output table
