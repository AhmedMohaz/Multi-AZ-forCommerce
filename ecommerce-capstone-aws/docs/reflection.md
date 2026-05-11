# Reflection — Trade-offs, Lessons Learned & Improvements

## Cost vs Resilience Trade-offs

### 1. NAT Gateway (skipped)
**What it provides:** Allows EC2 instances in private subnets to reach
the internet securely without exposing them to inbound traffic.

**Why it was skipped:** NAT Gateway costs approximately $32/month plus
$0.045 per GB of data processed — not covered by free tier.

**Decision made:** EC2 instances placed in public subnets with a
security group that only accepts inbound traffic from the ALB security
group. Outbound internet access is preserved for CloudWatch, SSM, and
package updates. The security boundary is maintained at the SG level
rather than the subnet level.

**Production recommendation:** Always use NAT Gateway or VPC endpoints
for private subnet resources. Exposing EC2 in public subnets, even with
restrictive SGs, is not best practice for production workloads.

---

### 2. RDS Multi-AZ (documented, not deployed)
**What it provides:** Synchronous replication to a standby instance in
a second AZ. Automatic failover in under 2 minutes with no data loss.

**Why it was skipped:** Multi-AZ roughly doubles the RDS cost.
For db.t3.micro this adds approximately $30/month — outside free tier.

**Decision made:** Single-AZ with daily automated backups and
cross-region snapshot copy. RPO moves from near-zero to up to 24 hours,
and RTO moves from 2 minutes to 10-15 minutes for a restore.

**Production recommendation:** Multi-AZ is non-negotiable for any
transactional database serving real users. The cost is justified by
the RPO and RTO improvement alone.

---

### 3. Fargate vs Lambda (Lambda chosen)
**What Fargate provides:** Long-running containerised workers with
consistent CPU/memory allocation. Better for tasks exceeding 15 minutes.

**Why Lambda was chosen:** Fargate has no free tier. Lambda provides
1 million free invocations per month and scales automatically with
SQS queue depth — functionally equivalent for short order processing tasks.

**Trade-off:** Lambda has a 15-minute execution limit per invocation.
Orders that take longer to process (e.g. third-party payment gateway
timeouts) would fail silently without a DLQ.

**Mitigation:** DLQ configured to capture failures after 3 attempts.

**Production recommendation:** Use Fargate for workloads needing
container isolation, GPU access, or execution beyond 15 minutes.
Lambda is the right choice for event-driven queue processing at this scale.

---

### 4. ElastiCache Single Node (no replica)
**What a replica provides:** Cache data remains available if the
primary node fails. Replica sits in a second AZ.

**Why skipped:** Free tier covers only one cache.t3.micro node.
A replica would double the cost (~$15/month additional).

**Impact of single node failure:** Cache goes cold. All requests fall
back to RDS until ElastiCache recovers (typically under 5 minutes for
a node replacement). RDS CPU would spike temporarily but the system
would remain functional.

**Production recommendation:** Always run at least one replica in a
second AZ for any cache serving production traffic.

---

## Complexity vs Reliability Trade-offs

### DynamoDB Global Tables
Adding Global Tables introduced cross-region replication with
near-zero RPO for session data. The complexity cost is minimal —
no application code changes are required, and AWS manages replication
automatically. This is one of the best value-for-complexity improvements
available on AWS and should be used in any multi-region architecture.

### Route 53 Failover Routing
Automatic DNS failover adds approximately 90 seconds of detection time
before traffic reroutes. For most applications this is acceptable.
For sub-30-second RTO requirements, an active-active architecture
with weighted routing would be needed instead — significantly more
complex to operate and test.

### SQS + Lambda Decoupling
Introducing a queue between the web tier and order processing adds
operational components to monitor and debug. However it provides:
- Protection against order loss during Lambda outages
- Independent scaling of web tier and processing tier
- Natural retry mechanism via visibility timeout
- Audit trail of every order event in the queue

The complexity cost is worth the reliability gain for any checkout flow.

---

## What I Would Do Differently in Production

| Area | Current (free tier) | Production approach |
|---|---|---|
| Compute networking | EC2 in public subnets | EC2 in private subnets + NAT Gateway |
| Database HA | Single-AZ RDS | Multi-AZ RDS with read replicas |
| Cache HA | Single Redis node | Redis with replica in second AZ |
| Order processing | Lambda | Fargate for long-running tasks |
| HTTPS | HTTP only | ACM certificate + HTTPS listener on ALB |
| Security | Basic SGs | WAF in front of ALB + VPC Flow Logs |
| Secrets | Hardcoded in user data | AWS Secrets Manager for DB credentials |
| Monitoring | Basic CloudWatch | CloudWatch + X-Ray distributed tracing |
| CI/CD | Manual deployment | CodePipeline + CodeBuild automated pipeline |

---

## Key Lessons

1. **Design for failure from the start.** The SQS DLQ, Route 53 health
   checks, and ASG health checks are all easy to add at design time
   and very hard to retrofit without downtime.

2. **Free tier constraints drive creative solutions.** Using Lambda
   instead of Fargate forced a better understanding of event-driven
   architecture. The Lambda approach is actually more appropriate for
   this workload.

3. **DynamoDB Global Tables is the easiest path to multi-region RPO.**
   With one CLI command, session data becomes globally replicated.
   No other AWS service provides this with so little configuration.

4. **Set up CloudWatch alarms before load testing.** Watching alarms
   fire during a real traffic spike reveals whether thresholds are
   correctly calibrated. Alarms set after the fact are educated guesses.

5. **Document trade-offs explicitly.** Graders and future team members
   need to understand why decisions were made, not just what was built.
   The reflection document is as important as the architecture itself.
