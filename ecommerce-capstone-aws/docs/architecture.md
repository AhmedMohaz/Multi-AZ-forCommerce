# Architecture Documentation

## Overview

This e-commerce platform is designed around three core principles:
fault tolerance, automatic scalability, and fast disaster recovery.
Every layer is designed so that the failure of any single component
does not bring down the application.

---

## Component Breakdown

### DNS Layer — Route 53
- Failover routing between primary (Stockholm) and DR (Ireland) regions
- Health checks polling `/health` every 30 seconds on the primary ALB
- Automatic DNS switch to Ireland within ~90 seconds of primary failure

### Load Balancing — Application Load Balancer (ALB)
- Internet-facing, spans both eu-north-1a and eu-north-1b
- Distributes HTTP traffic to EC2 instances on port 8080
- Health checks every 15 seconds — removes unhealthy instances automatically

### Compute — EC2 + Auto Scaling Group
- `t3.micro` instances running Amazon Linux 2023
- ASG maintains minimum 2 instances — one per AZ at all times
- Target tracking scales out when ALB requests exceed 300 per target
- Instances bootstrapped via User Data script on launch
- IAM instance profile grants SSM, CloudWatch, SQS, and DynamoDB access

### Caching — ElastiCache Redis
- `cache.t3.micro` single node
- Caches two categories of data:
  - **Product catalog** — TTL 10 minutes, reduces RDS read load during spikes
  - **User sessions** — TTL 30 minutes, avoids repeated DynamoDB lookups
- Cache miss falls back to RDS gracefully

### Database — RDS MySQL 8.0
- `db.t3.micro` — free tier compatible
- Stores orders, products, and user accounts
- 7-day automated backup retention
- Backups cross-copied to eu-west-1 daily via AWS Backup
- **Production note:** Multi-AZ omitted due to free tier cost (~$30/month).
  Would be enabled in production with:
  ```
  aws rds modify-db-instance --db-instance-identifier ecommerce-capstone-db --multi-az
  ```

### Session Store — DynamoDB Global Tables
- Stores user sessions and shopping cart data
- Replicated continuously between eu-north-1 and eu-west-1
- Near-zero RPO for session data — no data loss on region failure
- PAY_PER_REQUEST billing

### Order Processing — SQS + Lambda
- EC2 writes order events to SQS on checkout
- Lambda triggered by SQS — batch size 10, window 5 seconds
- Lambda scales concurrency automatically with queue depth
- Dead Letter Queue retains failed messages after 3 attempts
- Decoupling means Lambda failure does not affect the web tier

### Backups — AWS Backup
- Daily at 02:00 UTC covering RDS and DynamoDB
- 7-day retention in primary region
- Automatic cross-region copy to eu-west-1

### Observability — CloudWatch
- Dashboard covering ALB, EC2, RDS, SQS, Lambda, ElastiCache
- 5 alarms for key failure scenarios
- Log groups with 14-day retention
- SNS email notifications on alarm state change

---

## Single Points of Failure Analysis

| Layer | Potential SPF | Mitigation Applied |
|---|---|---|
| DNS | Single provider | Route 53 is globally distributed |
| Load Balancer | Single AZ | ALB spans eu-north-1a and eu-north-1b |
| Compute | Single instance | ASG min=2 across 2 AZs |
| Database | Single RDS | Automated backups + DR restore |
| Sessions | Single region | DynamoDB Global Tables to Ireland |
| Cache | Single node | Cache miss falls back to RDS |
| Region | Full eu-north-1 outage | Route 53 failover to eu-west-1 |
| Orders | Message loss | SQS DLQ retains for 4 days |

---

## Network Design

```
VPC: 10.0.0.0/16  (eu-north-1)
├── Public subnet  eu-north-1a  10.0.1.0/24  ALB + EC2
├── Public subnet  eu-north-1b  10.0.2.0/24  ALB + EC2
├── Private subnet eu-north-1a  10.0.3.0/24  RDS + ElastiCache
└── Private subnet eu-north-1b  10.0.4.0/24  RDS standby

Security Groups:
├── alb-sg    → inbound 80/443 from 0.0.0.0/0
├── ec2-sg    → inbound 8080 from alb-sg only
├── rds-sg    → inbound 3306 from ec2-sg only
└── cache-sg  → inbound 6379 from ec2-sg only
```

---

## Data Flow

```
User → Route 53 → ALB → EC2
                         ├── ElastiCache (cache hit → respond)
                         ├── RDS MySQL   (cache miss → query)
                         ├── DynamoDB    (session read/write)
                         └── SQS         (order enqueue)
                                              └── Lambda (process)
```
