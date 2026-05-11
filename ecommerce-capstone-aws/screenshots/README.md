# Screenshots — Evidence Folder

This folder stores console screenshots taken during deployment and testing.
They are referenced in the docs as supporting evidence.

## Expected Screenshots

| Filename | What to capture | When to take it |
|---|---|---|
| `alb-healthy-targets.png` | EC2 → Load Balancers → your ALB → Target groups tab showing healthy instances | After ASG instances launch |
| `asg-scaling-activity.png` | EC2 → Auto Scaling Groups → Activity tab showing scale-out events | During Artillery load test |
| `rds-instance.png` | RDS → Databases → your instance → Summary showing status and configuration | After RDS is available |
| `dynamodb-replicas.png` | DynamoDB → Tables → ecommerce-capstone-sessions → Global Tables tab | After running 01-dynamodb.sh |
| `cloudwatch-dashboard.png` | CloudWatch → Dashboards → ecommerce-capstone showing all widgets | After load test completes |
| `cloudwatch-alarms.png` | CloudWatch → Alarms showing all 5 alarms and their state | After running 04-alarms.sh |
| `route53-records.png` | Route 53 → Hosted zones → your zone → showing PRIMARY and SECONDARY records | After running 03-route53.sh |
| `sqs-queues.png` | SQS → showing both orders queue and DLQ | After running 02-sqs.sh |
| `lambda-trigger.png` | Lambda → ecommerce-order-processor → Configuration → Triggers tab | After creating the Lambda |
| `failover-test-output.png` | Terminal output from running 09-dr-test.sh | After DR simulation |
