#!/bin/bash
# Phase 2 — SQS Queues
source scripts/00-setup.sh

echo "Creating Dead Letter Queue..."
DLQ_URL=$(aws sqs create-queue \
  --queue-name "$APP_NAME-orders-dlq" \
  --region $AWS_REGION \
  --query 'QueueUrl' --output text)

DLQ_ARN=$(aws sqs get-queue-attributes \
  --queue-url $DLQ_URL \
  --attribute-names QueueArn \
  --region $AWS_REGION \
  --query 'Attributes.QueueArn' --output text)

echo "DLQ ARN: $DLQ_ARN"

echo "Creating main orders queue with DLQ..."
QUEUE_URL=$(aws sqs create-queue \
  --queue-name "$APP_NAME-orders" \
  --attributes "{
    \"VisibilityTimeout\": \"30\",
    \"MessageRetentionPeriod\": \"345600\",
    \"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"
  }" \
  --region $AWS_REGION \
  --query 'QueueUrl' --output text)

echo "Queue URL: $QUEUE_URL"
echo "SQS queues created successfully"
