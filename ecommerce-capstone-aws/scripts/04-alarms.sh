#!/bin/bash
# Phase 4 — CloudWatch Alarms + SNS
source scripts/00-setup.sh

# SNS topic for notifications
SNS_ARN=$(aws sns create-topic \
  --name "$APP_NAME-alerts" \
  --region $AWS_REGION \
  --query 'TopicArn' --output text)

echo "SNS Topic: $SNS_ARN"
echo "Subscribe your email to receive alarm notifications:"
echo "  aws sns subscribe --topic-arn $SNS_ARN --protocol email --notification-endpoint your@email.com --region $AWS_REGION"

# Get ALB + TG dimension values
ALB_SUFFIX=$(aws elbv2 describe-load-balancers \
  --names $APP_NAME-alb \
  --region $AWS_REGION \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text | sed 's|.*:loadbalancer/||')

TG_SUFFIX=$(aws elbv2 describe-target-groups \
  --names $APP_NAME-tg \
  --region $AWS_REGION \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text | sed 's|.*:targetgroup/|targetgroup/|')

echo "Creating 5 CloudWatch alarms..."

# 1. High 5xx errors
aws cloudwatch put-metric-alarm \
  --alarm-name "High5xxErrors" \
  --metric-name HTTPCode_Target_5XX_Count \
  --namespace AWS/ApplicationELB \
  --dimensions Name=LoadBalancer,Value=$ALB_SUFFIX \
  --statistic Sum --period 60 --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions $SNS_ARN \
  --alarm-description "More than 5 errors/min for 2 consecutive minutes" \
  --region $AWS_REGION

# 2. Unhealthy hosts
aws cloudwatch put-metric-alarm \
  --alarm-name "UnhealthyTargets" \
  --metric-name UnHealthyHostCount \
  --namespace AWS/ApplicationELB \
  --dimensions \
    Name=LoadBalancer,Value=$ALB_SUFFIX \
    Name=TargetGroup,Value=$TG_SUFFIX \
  --statistic Average --period 60 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 1 \
  --alarm-actions $SNS_ARN \
  --alarm-description "At least 1 unhealthy target in ALB target group" \
  --region $AWS_REGION

# 3. SQS queue backlog
aws cloudwatch put-metric-alarm \
  --alarm-name "OrderQueueBacklog" \
  --metric-name ApproximateNumberOfMessagesVisible \
  --namespace AWS/SQS \
  --dimensions Name=QueueName,Value=$APP_NAME-orders \
  --statistic Average --period 60 --threshold 50 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions $SNS_ARN \
  --alarm-description "Order queue has 50+ unprocessed messages for 2 minutes" \
  --region $AWS_REGION

# 4. RDS high CPU
aws cloudwatch put-metric-alarm \
  --alarm-name "HighRDSCPU" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value=$APP_NAME-db \
  --statistic Average --period 300 --threshold 75 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions $SNS_ARN \
  --alarm-description "RDS CPU above 75% for 10 consecutive minutes" \
  --region $AWS_REGION

# 5. Lambda errors
aws cloudwatch put-metric-alarm \
  --alarm-name "LambdaOrderErrors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --dimensions Name=FunctionName,Value=ecommerce-order-processor \
  --statistic Sum --period 60 --threshold 3 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions $SNS_ARN \
  --alarm-description "Lambda order processor has 3+ errors in 1 minute" \
  --region $AWS_REGION

echo "All alarms created. Current state:"
aws cloudwatch describe-alarms \
  --region $AWS_REGION \
  --query 'MetricAlarms[].{Alarm:AlarmName,State:StateValue}' \
  --output table
