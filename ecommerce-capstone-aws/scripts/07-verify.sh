#!/bin/bash
# Phase 7 — Verify all resources are healthy
source scripts/00-setup.sh

echo "=============================================="
echo " CAPSTONE RESOURCE VERIFICATION"
echo " Region: $AWS_REGION"
echo "=============================================="

echo -e "\n-- Application Load Balancer --"
aws elbv2 describe-load-balancers \
  --names $APP_NAME-alb \
  --region $AWS_REGION \
  --query 'LoadBalancers[0].{State:State.Code,AZs:AvailabilityZones[].ZoneName}' \
  --output table

echo -e "\n-- Target Group Health --"
TG_ARN=$(aws elbv2 describe-target-groups \
  --names $APP_NAME-tg \
  --region $AWS_REGION \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region $AWS_REGION \
  --query 'TargetHealthDescriptions[].{ID:Target.Id,Port:Target.Port,State:TargetHealth.State}' \
  --output table

echo -e "\n-- Auto Scaling Group --"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $APP_NAME-asg \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity,AZs:AvailabilityZones}' \
  --output table

echo -e "\n-- RDS Instance --"
aws rds describe-db-instances \
  --db-instance-identifier $APP_NAME-db \
  --region $AWS_REGION \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Class:DBInstanceClass,MultiAZ:MultiAZ,AZ:AvailabilityZone}' \
  --output table

echo -e "\n-- DynamoDB Global Table Replicas --"
aws dynamodb describe-table \
  --table-name "$APP_NAME-sessions" \
  --region $AWS_REGION \
  --query 'Table.Replicas[].{Region:RegionName,Status:ReplicaStatus}' \
  --output table

echo -e "\n-- SQS Queues --"
for Q in "$APP_NAME-orders" "$APP_NAME-orders-dlq"; do
  URL=$(aws sqs get-queue-url --queue-name $Q --region $AWS_REGION --query 'QueueUrl' --output text 2>/dev/null)
  if [ -n "$URL" ]; then
    echo "  $Q — OK"
  else
    echo "  $Q — NOT FOUND"
  fi
done

echo -e "\n-- Lambda Function --"
aws lambda get-function \
  --function-name ecommerce-order-processor \
  --region $AWS_REGION \
  --query 'Configuration.{State:State,Runtime:Runtime,LastModified:LastModified}' \
  --output table 2>/dev/null || echo "  Lambda not found"

echo -e "\n-- CloudWatch Alarms --"
aws cloudwatch describe-alarms \
  --region $AWS_REGION \
  --query 'MetricAlarms[].{Alarm:AlarmName,State:StateValue}' \
  --output table

echo -e "\n-- CloudWatch Log Groups --"
aws logs describe-log-groups \
  --log-group-name-prefix "/ecommerce-capstone" \
  --region $AWS_REGION \
  --query 'logGroups[].{Name:logGroupName,Retention:retentionInDays}' \
  --output table

echo -e "\n=============================================="
echo " Verification complete: $(date)"
echo "=============================================="
