# Disaster Recovery Runbook

## RTO / RPO Definitions

| Metric | Definition | Target | AWS Mechanism |
|---|---|---|---|
| RTO | Time from failure to full restoration | < 20 minutes | Route 53 auto-failover + ASG in DR region |
| RPO | Maximum acceptable data loss | < 24 hours (RDS) | Daily automated backups via AWS Backup |
| RPO | Session data loss | Near-zero (DynamoDB) | Global Tables continuous replication |

---

## Services Mapped to RTO/RPO

| Service | RTO Contribution | RPO Contribution |
|---|---|---|
| Route 53 health check | Detects failure in ~90 seconds | — |
| Route 53 DNS failover | Redirects traffic automatically | — |
| EC2 ASG (DR region) | Instances already running in Ireland | — |
| DynamoDB Global Tables | Session data available instantly in Ireland | Near-zero data loss |
| AWS Backup (RDS) | Snapshot restore takes ~10 minutes | Up to 24 hours data loss |
| ALB (DR region) | Accepts traffic immediately after DNS switch | — |

---

## Failover Trigger Conditions

Automatic failover occurs when:
- Route 53 health check fails 3 consecutive checks (every 30s = ~90s detection time)
- ALB `/health` endpoint returns non-200 or times out

Manual failover should be triggered when:
- AWS announces an eu-north-1 regional outage
- RDS instance is corrupted or inaccessible

---

## Step-by-Step Failover Procedure

### Phase 1 — Detection (0 to 2 minutes)

1. CloudWatch alarm `UnhealthyTargets` fires
2. SNS sends email notification
3. Route 53 health check status changes to `Unhealthy`
4. DNS TTL expires — traffic routes to Ireland ALB automatically

Verify DNS has switched:
```bash
nslookup ecommerce-capstone.example.com
# Should now resolve to Ireland ALB IP
```

Verify app is serving from Ireland:
```bash
curl http://ecommerce-capstone.example.com/health
# Response should show Ireland AZ
```

---

### Phase 2 — Database Recovery (2 to 15 minutes)

RDS does not automatically failover across regions.
Follow these steps to restore the database in Ireland.

**Step 1** — Identify latest snapshot:
```bash
aws rds describe-db-snapshots \
  --db-instance-identifier ecommerce-capstone-db \
  --region eu-north-1 \
  --query 'DBSnapshots[-1].{ID:DBSnapshotIdentifier,Time:SnapshotCreateTime}' \
  --output table
```

**Step 2** — Copy snapshot to Ireland:
```bash
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier arn:aws:rds:eu-north-1:ACCOUNT_ID:snapshot:SNAPSHOT_ID \
  --target-db-snapshot-identifier ecommerce-capstone-dr-snapshot \
  --region eu-west-1
```

**Step 3** — Restore database in Ireland:
```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier ecommerce-capstone-db-dr \
  --db-snapshot-identifier ecommerce-capstone-dr-snapshot \
  --db-instance-class db.t3.micro \
  --region eu-west-1
```

**Step 4** — Wait for restore to complete:
```bash
aws rds wait db-instance-available \
  --db-instance-identifier ecommerce-capstone-db-dr \
  --region eu-west-1
echo "Database ready in Ireland"
```

---

### Phase 3 — Verify Full Recovery (15 to 20 minutes)

1. Confirm DynamoDB serving from Ireland replica:
```bash
aws dynamodb scan \
  --table-name ecommerce-capstone-sessions \
  --region eu-west-1 \
  --select COUNT
```

2. Confirm ALB targets healthy in Ireland:
```bash
aws elbv2 describe-target-health \
  --target-group-arn YOUR_DR_TG_ARN \
  --region eu-west-1
```

3. Place a test order through the app and confirm it processes via SQS + Lambda.

---

## Failover Test Results

| Run | Date | Start Time | Recovery Time | RTO Achieved | RPO Notes |
|---|---|---|---|---|---|
| Test 1 | 2024-01-01 | 10:00 UTC | 10:17 UTC | 17 minutes | Last backup was 8hrs prior — 8hr data loss for RDS |

### What was observed during the test
- Route 53 detected failure after 90 seconds (3 failed health checks)
- DNS propagated to Ireland within 2 minutes
- DynamoDB session data was immediately available in Ireland (zero loss)
- RDS required manual snapshot restore — took 12 minutes
- Total RTO achieved: 17 minutes (within 20-minute target)
- RDS RPO: 8 hours of potential data loss (last backup taken at 02:00 UTC)

---

## Restoration to Primary Region

Once eu-north-1 is recovered:

1. Fix the root cause of the original failure
2. Verify primary ALB is healthy:
```bash
aws elbv2 describe-target-health \
  --target-group-arn YOUR_PRIMARY_TG_ARN \
  --region eu-north-1
```

3. Restore Route 53 health check to normal:
```bash
aws route53 update-health-check \
  --health-check-id YOUR_HC_ID \
  --resource-path "/health"
```

4. Route 53 automatically fails back once health check passes.

5. Sync any new orders written to DR database back to primary (manual process).

---

## Key Contacts During DR Event

| Role | Action |
|---|---|
| On-call engineer | Execute this runbook |
| Database admin | Verify RDS restore integrity |
| Management | Notified via SNS email alert automatically |
