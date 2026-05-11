#!/bin/bash
# Phase 3 — Route 53 Failover Routing
source scripts/00-setup.sh

# Get ALB details — primary
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names $APP_NAME-alb \
  --region $AWS_REGION \
  --query 'LoadBalancers[0].DNSName' --output text)

ALB_ZONE=$(aws elbv2 describe-load-balancers \
  --names $APP_NAME-alb \
  --region $AWS_REGION \
  --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text)

# Get ALB details — DR
DR_ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names $APP_NAME-alb \
  --region $DR_REGION \
  --query 'LoadBalancers[0].DNSName' --output text)

DR_ALB_ZONE=$(aws elbv2 describe-load-balancers \
  --names $APP_NAME-alb \
  --region $DR_REGION \
  --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text)

echo "Primary ALB : $ALB_DNS"
echo "DR ALB      : $DR_ALB_DNS"

# Create hosted zone
HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
  --name "$APP_NAME.example.com" \
  --caller-reference "$(date +%s)" \
  --query 'HostedZone.Id' --output text | sed 's|/hostedzone/||')
echo "Hosted Zone : $HOSTED_ZONE_ID"

# Create health check on primary ALB
PRIMARY_HC=$(aws route53 create-health-check \
  --caller-reference "primary-$(date +%s)" \
  --health-check-config "{
    \"Type\": \"HTTP\",
    \"FullyQualifiedDomainName\": \"$ALB_DNS\",
    \"ResourcePath\": \"/health\",
    \"Port\": 80,
    \"RequestInterval\": 30,
    \"FailureThreshold\": 3
  }" \
  --query 'HealthCheck.Id' --output text)

aws route53 change-tags-for-resource \
  --resource-type healthcheck \
  --resource-id $PRIMARY_HC \
  --add-tags Key=Name,Value=primary-stockholm-hc

echo "Health Check: $PRIMARY_HC"

# Primary DNS record
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"CREATE\",
      \"ResourceRecordSet\": {
        \"Name\": \"$APP_NAME.example.com\",
        \"Type\": \"A\",
        \"SetIdentifier\": \"primary-stockholm\",
        \"Failover\": \"PRIMARY\",
        \"HealthCheckId\": \"$PRIMARY_HC\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$ALB_ZONE\",
          \"DNSName\": \"$ALB_DNS\",
          \"EvaluateTargetHealth\": true
        }
      }
    }]
  }"

# Secondary DNS record
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"CREATE\",
      \"ResourceRecordSet\": {
        \"Name\": \"$APP_NAME.example.com\",
        \"Type\": \"A\",
        \"SetIdentifier\": \"secondary-ireland\",
        \"Failover\": \"SECONDARY\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$DR_ALB_ZONE\",
          \"DNSName\": \"$DR_ALB_DNS\",
          \"EvaluateTargetHealth\": true
        }
      }
    }]
  }"

echo "Route 53 failover routing configured"
echo "Save these values:"
echo "  HOSTED_ZONE_ID=$HOSTED_ZONE_ID"
echo "  PRIMARY_HC=$PRIMARY_HC"
