#!/bin/bash
# Phase 0 — Environment variables
# Source this file before running any other script:
#   source scripts/00-setup.sh

export AWS_REGION="eu-north-1"
export DR_REGION="eu-west-1"
export APP_NAME="ecommerce-capstone"
export DB_PASSWORD="CapstoneSecure2024!"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "AWS_REGION  : $AWS_REGION"
echo "DR_REGION   : $DR_REGION"
echo "APP_NAME    : $APP_NAME"
echo "ACCOUNT_ID  : $ACCOUNT_ID"
