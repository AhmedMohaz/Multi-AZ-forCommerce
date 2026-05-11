#!/bin/bash
# Phase 5 — CloudWatch Log Groups
source scripts/00-setup.sh

for GROUP in \
  "/ecommerce-capstone/application" \
  "/ecommerce-capstone/rds" \
  "/ecommerce-capstone/lambda"; do

  aws logs create-log-group \
    --log-group-name $GROUP \
    --region $AWS_REGION

  aws logs put-retention-policy \
    --log-group-name $GROUP \
    --retention-in-days 14 \
    --region $AWS_REGION

  echo "Created: $GROUP (14-day retention)"
done
