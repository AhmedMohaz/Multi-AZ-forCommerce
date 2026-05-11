#!/bin/bash
# =============================================================
#  AWS CAPSTONE CLEANUP SCRIPT
#  Deletes every resource created in the ecommerce-capstone project
#  Regions: eu-north-1 (Stockholm) + eu-west-1 (Ireland DR)
# =============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()     { echo -e "${GREEN}[DONE]${NC}  $1"; }
warn()   { echo -e "${YELLOW}[SKIP]${NC}  $1 (not found or already deleted)"; }

APP_NAME="ecommerce-capstone"
PRIMARY="eu-north-1"
DR="eu-west-1"

echo -e "${RED}=================================================${NC}"
echo -e "${RED}  CAPSTONE CLEANUP — DELETES ALL RESOURCES       ${NC}"
echo -e "${RED}=================================================${NC}"
read -p "Type YES to continue: " CONFIRM
[ "$CONFIRM" != "YES" ] && echo "Aborted." && exit 0

try_delete() { eval "$1" 2>/dev/null && ok "$2" || warn "$2"; }

log "=== Route 53 ==="
HZ_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?contains(Name,'$APP_NAME')].Id" \
  --output text 2>/dev/null | sed 's|/hostedzone/||')
if [ -n "$HZ_ID" ]; then
  RECORDS=$(aws route53 list-resource-record-sets --hosted-zone-id "$HZ_ID" \
    --query "ResourceRecordSets[?Type!='NS'&&Type!='SOA']" --output json 2>/dev/null)
  CHANGES=$(echo "$RECORDS" | python3 -c "
import json,sys
r=json.load(sys.stdin)
print(json.dumps({'Changes':[{'Action':'DELETE','ResourceRecordSet':x} for x in r]}))" 2>/dev/null)
  [ "$CHANGES" != '{"Changes": []}' ] && \
    aws route53 change-resource-record-sets --hosted-zone-id "$HZ_ID" \
      --change-batch "$CHANGES" > /dev/null 2>&1 && ok "DNS records deleted"
  try_delete "aws route53 delete-hosted-zone --id $HZ_ID" "Hosted zone deleted"
fi

HC_IDS=$(aws route53 list-health-checks --query "HealthChecks[].Id" --output text 2>/dev/null)
for HC in $HC_IDS; do
  TAG=$(aws route53 list-tags-for-resource --resource-type healthcheck --resource-id "$HC" \
    --query "ResourceTagSet.Tags[?Key=='Name'].Value" --output text 2>/dev/null)
  [[ "$TAG" == *"$APP_NAME"* ]] || [[ "$TAG" == *"stockholm"* ]] && \
    try_delete "aws route53 delete-health-check --health-check-id $HC" "Health check deleted"
done

log "=== PRIMARY REGION: $PRIMARY ==="
try_delete "aws autoscaling delete-auto-scaling-group --auto-scaling-group-name $APP_NAME-asg --force-delete --region $PRIMARY" "ASG deleted"
sleep 20

LT_ID=$(aws ec2 describe-launch-templates --filters "Name=launch-template-name,Values=$APP_NAME-lt" \
  --region $PRIMARY --query 'LaunchTemplates[0].LaunchTemplateId' --output text 2>/dev/null)
[ "$LT_ID" != "None" ] && try_delete "aws ec2 delete-launch-template --launch-template-id $LT_ID --region $PRIMARY" "Launch template deleted"

ALB_ARN=$(aws elbv2 describe-load-balancers --names $APP_NAME-alb --region $PRIMARY \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ "$ALB_ARN" != "None" ] && [ -n "$ALB_ARN" ]; then
  for L in $(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --region $PRIMARY \
    --query 'Listeners[].ListenerArn' --output text 2>/dev/null); do
    try_delete "aws elbv2 delete-listener --listener-arn $L --region $PRIMARY" "Listener deleted"
  done
  try_delete "aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN --region $PRIMARY" "ALB deleted"
  sleep 30
fi
TG_ARN=$(aws elbv2 describe-target-groups --names $APP_NAME-tg --region $PRIMARY \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
[ "$TG_ARN" != "None" ] && try_delete "aws elbv2 delete-target-group --target-group-arn $TG_ARN --region $PRIMARY" "Target group deleted"

try_delete "aws elasticache delete-cache-cluster --cache-cluster-id $APP_NAME-redis --region $PRIMARY" "ElastiCache deletion initiated"

aws rds modify-db-instance --db-instance-identifier $APP_NAME-db --no-deletion-protection \
  --apply-immediately --region $PRIMARY > /dev/null 2>&1 || true
try_delete "aws rds delete-db-instance --db-instance-identifier $APP_NAME-db --skip-final-snapshot --region $PRIMARY" "RDS deletion initiated"

for Q in "$APP_NAME-orders" "$APP_NAME-orders-dlq"; do
  Q_URL=$(aws sqs get-queue-url --queue-name $Q --region $PRIMARY --query 'QueueUrl' --output text 2>/dev/null)
  [ -n "$Q_URL" ] && try_delete "aws sqs delete-queue --queue-url $Q_URL --region $PRIMARY" "SQS $Q deleted"
done

MAPPING=$(aws lambda list-event-source-mappings --function-name ecommerce-order-processor \
  --region $PRIMARY --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null)
[ "$MAPPING" != "None" ] && try_delete "aws lambda delete-event-source-mapping --uuid $MAPPING --region $PRIMARY" "Lambda trigger removed"
try_delete "aws lambda delete-function --function-name ecommerce-order-processor --region $PRIMARY" "Lambda deleted"

try_delete "aws dynamodb update-table --table-name $APP_NAME-sessions \
  --replica-updates '[{\"Delete\":{\"RegionName\":\"$DR\"}}]' --region $PRIMARY" "DynamoDB replica removal initiated"
sleep 30
try_delete "aws dynamodb delete-table --table-name $APP_NAME-sessions --region $PRIMARY" "DynamoDB table deleted"

try_delete "aws cloudwatch delete-alarms \
  --alarm-names High5xxErrors UnhealthyTargets OrderQueueBacklog HighRDSCPU LambdaOrderErrors \
  --region $PRIMARY" "CloudWatch alarms deleted"

for LG in /ecommerce-capstone/application /ecommerce-capstone/rds /ecommerce-capstone/lambda; do
  try_delete "aws logs delete-log-group --log-group-name $LG --region $PRIMARY" "Log group $LG deleted"
done
try_delete "aws cloudwatch delete-dashboards --dashboard-names $APP_NAME --region $PRIMARY" "Dashboard deleted"

SNS_ARN=$(aws sns list-topics --region $PRIMARY \
  --query "Topics[?ends_with(TopicArn,'$APP_NAME-alerts')].TopicArn" --output text 2>/dev/null)
[ -n "$SNS_ARN" ] && try_delete "aws sns delete-topic --topic-arn $SNS_ARN --region $PRIMARY" "SNS deleted"

log "Waiting for RDS + ElastiCache to finish deleting..."
aws rds wait db-instance-deleted --db-instance-identifier $APP_NAME-db --region $PRIMARY 2>/dev/null || true
try_delete "aws rds delete-db-subnet-group --db-subnet-group-name $APP_NAME-db-subnet --region $PRIMARY" "RDS subnet group deleted"
sleep 60
try_delete "aws elasticache delete-cache-subnet-group --cache-subnet-group-name $APP_NAME-cache-subnet --region $PRIMARY" "ElastiCache subnet group deleted"

log "Deleting security groups..."
for SG in $APP_NAME-alb-sg $APP_NAME-ec2-sg $APP_NAME-rds-sg $APP_NAME-cache-sg; do
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG" \
    --region $PRIMARY --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
  [ "$SG_ID" != "None" ] && try_delete "aws ec2 delete-security-group --group-id $SG_ID --region $PRIMARY" "$SG deleted"
done

log "Deleting VPC..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$APP_NAME" \
  --region $PRIMARY --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
  for SN in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $PRIMARY --query 'Subnets[].SubnetId' --output text 2>/dev/null); do
    try_delete "aws ec2 delete-subnet --subnet-id $SN --region $PRIMARY" "Subnet $SN deleted"
  done
  for RT in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $PRIMARY --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null); do
    try_delete "aws ec2 delete-route-table --route-table-id $RT --region $PRIMARY" "Route table deleted"
  done
  for IGW in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --region $PRIMARY --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null); do
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID --region $PRIMARY > /dev/null 2>&1 || true
    try_delete "aws ec2 delete-internet-gateway --internet-gateway-id $IGW --region $PRIMARY" "IGW deleted"
  done
  try_delete "aws ec2 delete-vpc --vpc-id $VPC_ID --region $PRIMARY" "VPC deleted"
fi

log "Deleting IAM role..."
for P in $(aws iam list-attached-role-policies --role-name $APP_NAME-ec2-role \
  --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
  try_delete "aws iam detach-role-policy --role-name $APP_NAME-ec2-role --policy-arn $P" "Policy detached"
done
try_delete "aws iam remove-role-from-instance-profile --instance-profile-name $APP_NAME-ec2-role --role-name $APP_NAME-ec2-role" "Role removed from profile"
try_delete "aws iam delete-instance-profile --instance-profile-name $APP_NAME-ec2-role" "Instance profile deleted"
try_delete "aws iam delete-role --role-name $APP_NAME-ec2-role" "IAM role deleted"

log "=== DR REGION: $DR ==="
try_delete "aws autoscaling delete-auto-scaling-group --auto-scaling-group-name $APP_NAME-asg --force-delete --region $DR" "DR ASG deleted"
sleep 15

DR_ALB_ARN=$(aws elbv2 describe-load-balancers --names $APP_NAME-alb --region $DR \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ "$DR_ALB_ARN" != "None" ] && [ -n "$DR_ALB_ARN" ]; then
  for L in $(aws elbv2 describe-listeners --load-balancer-arn "$DR_ALB_ARN" --region $DR \
    --query 'Listeners[].ListenerArn' --output text 2>/dev/null); do
    try_delete "aws elbv2 delete-listener --listener-arn $L --region $DR" "DR listener deleted"
  done
  try_delete "aws elbv2 delete-load-balancer --load-balancer-arn $DR_ALB_ARN --region $DR" "DR ALB deleted"
  sleep 20
fi

DR_VPC=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$APP_NAME" \
  --region $DR --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ "$DR_VPC" != "None" ] && [ -n "$DR_VPC" ]; then
  for SN in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DR_VPC" \
    --region $DR --query 'Subnets[].SubnetId' --output text 2>/dev/null); do
    try_delete "aws ec2 delete-subnet --subnet-id $SN --region $DR" "DR subnet deleted"
  done
  for IGW in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$DR_VPC" \
    --region $DR --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null); do
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $DR_VPC --region $DR > /dev/null 2>&1 || true
    try_delete "aws ec2 delete-internet-gateway --internet-gateway-id $IGW --region $DR" "DR IGW deleted"
  done
  try_delete "aws ec2 delete-vpc --vpc-id $DR_VPC --region $DR" "DR VPC deleted"
fi

echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}  CLEANUP COMPLETE: $(date)${NC}"
echo -e "${GREEN}=================================================${NC}"
