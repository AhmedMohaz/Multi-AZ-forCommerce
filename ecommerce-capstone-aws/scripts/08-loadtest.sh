#!/bin/bash
# Phase 8 — Run Artillery load test
source scripts/00-setup.sh

# Check Artillery is installed
if ! command -v artillery &> /dev/null; then
  echo "Installing Artillery..."
  npm install -g artillery
fi

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names $APP_NAME-alb \
  --region $AWS_REGION \
  --query 'LoadBalancers[0].DNSName' --output text)

echo "Target: http://$ALB_DNS"

# Update the loadtest.yml with the actual ALB DNS
sed -i "s|YOUR_ALB_DNS_HERE|$ALB_DNS|g" load-testing/loadtest.yml

echo "Running load test..."
echo "Watch ASG scaling in: EC2 → Auto Scaling Groups → Activity tab"
echo ""

artillery run load-testing/loadtest.yml \
  --output load-testing/results.json

echo "Generating HTML report..."
artillery report load-testing/results.json \
  --output load-testing/report.html

echo ""
echo "Results saved to load-testing/results.json"
echo "Report saved to load-testing/report.html"
echo "Open report.html in your browser to view full results"
