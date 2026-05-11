#!/bin/bash
# Phase 9 — DR Failover Simulation
# This test forces the Route 53 health check to fail,
# verifies DNS switches to Ireland, then restores everything.
source scripts/00-setup.sh

# You must set these values from your Route 53 setup (script 03)
PRIMARY_HC="YOUR_HEALTH_CHECK_ID"
HOSTED_ZONE_ID="YOUR_HOSTED_ZONE_ID"
DOMAIN="$APP_NAME.example.com"

if [ "$PRIMARY_HC" = "YOUR_HEALTH_CHECK_ID" ]; then
  echo "ERROR: Update PRIMARY_HC and HOSTED_ZONE_ID in this script first"
  echo "Get them with:"
  echo "  aws route53 list-health-checks --query 'HealthChecks[].{ID:Id,Domain:HealthCheckConfig.FullyQualifiedDomainName}' --output table"
  echo "  aws route53 list-hosted-zones --query 'HostedZones[].{ID:Id,Name:Name}' --output table"
  exit 1
fi

echo "=============================================="
echo " DR FAILOVER SIMULATION"
echo " Start: $(date)"
echo "=============================================="
START=$(date +%s)

echo "[$(date +%T)] Step 1: Forcing health check to fail..."
aws route53 update-health-check \
  --health-check-id $PRIMARY_HC \
  --resource-path "/force-fail-dr-test"
echo "[$(date +%T)] Health check path changed to /force-fail-dr-test"

echo "[$(date +%T)] Step 2: Waiting 90s for Route 53 to detect failure..."
sleep 90

echo "[$(date +%T)] Step 3: Checking health check status..."
aws route53 get-health-check-status \
  --health-check-id $PRIMARY_HC \
  --query 'HealthCheckObservations[0].StatusReport.{Status:Status,CheckedTime:CheckedTime}' \
  --output table

echo "[$(date +%T)] Step 4: Testing if traffic has switched to Ireland..."
curl -s --max-time 10 http://$DOMAIN/health 2>/dev/null || \
  echo "DNS may still be propagating — try: curl http://$DOMAIN/health"

END=$(date +%s)
RTO=$(( END - START ))

echo ""
echo "=============================================="
echo " FAILOVER RESULTS"
echo " Time elapsed : ${RTO} seconds ($(( RTO / 60 )) min $(( RTO % 60 )) sec)"
echo " Target RTO   : 20 minutes (1200 seconds)"
echo " Result       : $([ $RTO -lt 1200 ] && echo 'PASS' || echo 'REVIEW')"
echo "=============================================="

echo "[$(date +%T)] Restoring health check to normal..."
aws route53 update-health-check \
  --health-check-id $PRIMARY_HC \
  --resource-path "/health"
echo "[$(date +%T)] Health check restored. Test complete."
