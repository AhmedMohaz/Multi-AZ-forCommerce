# AWS E-Commerce Capstone — Resilient, Scalable & Recoverable Architecture

> **Primary Region:** eu-north-1 (Stockholm) | **DR Region:** eu-west-1 (Ireland)  
> **Course:** AWS DevOps Engineer — Domain 3: Resilient Cloud Solutions

---

## Architecture Overview

![Architecture Diagram](docs/architecture-diagram.png)

A production-style e-commerce platform built on AWS demonstrating high availability,
auto scaling, and disaster recovery across two AWS regions.

---

## Quick Links

| Deliverable | Location |
|---|---|
| Architecture explanation | [docs/architecture.md](docs/architecture.md) |
| DR Runbook | [docs/dr-runbook.md](docs/dr-runbook.md) |
| Scaling Test Report | [docs/scaling-test-report.md](docs/scaling-test-report.md) |
| Reflection & Trade-offs | [docs/reflection.md](docs/reflection.md) |
| CLI Scripts | [scripts/](scripts/) |
| Load Test Config | [load-testing/loadtest.yml](load-testing/loadtest.yml) |

---

## Infrastructure Summary

| Component | Service | Configuration |
|---|---|---|
| DNS & Failover | Route 53 | Failover routing + health checks |
| Load Balancer | ALB | Internet-facing, HTTP:80, 2 AZs |
| Compute | EC2 t3.micro | ASG min=2, max=4, target tracking |
| Database | RDS MySQL 8.0 db.t3.micro | Single-AZ + 7-day automated backups |
| Session Store | DynamoDB | Global Tables — Stockholm + Ireland |
| Cache | ElastiCache Redis cache.t3.micro | Product catalog + session caching |
| Order Queue | SQS Standard | DLQ after 3 failures |
| Order Processing | Lambda | SQS trigger, batch size 10 |
| Monitoring | CloudWatch | 5 alarms + dashboard + log groups |
| Backups | AWS Backup | Daily, 7-day retention, copied to eu-west-1 |
| Notifications | SNS | Email alerts on alarm state change |

---

## RTO / RPO Targets

| Metric | Target | Mechanism |
|---|---|---|
| RTO | < 20 minutes | Route 53 failover + RDS snapshot restore |
| RPO | < 24 hours | RDS daily automated backups |
| RPO (DynamoDB) | Near-zero | Global Tables continuous replication |

---

## Deployment Order

```bash
# 1. Set environment
bash scripts/00-setup.sh

# 2. Create DynamoDB Global Tables
bash scripts/01-dynamodb.sh

# 3. Create SQS queues
bash scripts/02-sqs.sh

# 4. Set up Route 53 failover
bash scripts/03-route53.sh

# 5. Create CloudWatch alarms
bash scripts/04-alarms.sh

# 6. Create log groups
bash scripts/05-logs.sh

# 7. Configure AWS Backup
bash scripts/06-backup.sh

# 8. Verify all resources
bash scripts/07-verify.sh

# 9. Run load test
bash scripts/08-loadtest.sh

# 10. Simulate DR failover
bash scripts/09-dr-test.sh

# Cleanup when done
bash cleanup.sh
```

---

## Free Tier Notes

This project is designed to run within AWS Free Tier limits (eu-north-1):

| Service | Free Tier Limit | Decision |
|---|---|---|
| EC2 t3.micro | 750 hrs/month | Used — monitor hours |
| RDS db.t3.micro | 750 hrs/month | Used — Single-AZ only |
| DynamoDB | 25 GB storage | Used — minimal test data |
| SQS | 1M requests/month | Used |
| Lambda | 1M invocations/month | Used instead of Fargate |
| ALB | 750 hrs/month | Used |
| NAT Gateway | Not free (~$32/month) | Skipped — EC2 in public subnets |
| RDS Multi-AZ | Not free (~$30/month) | Documented only |
| Fargate | Not free | Replaced with Lambda |

See [docs/reflection.md](docs/reflection.md) for full trade-off discussion.
