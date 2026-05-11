#!/bin/bash
# Phase 6 — Manual RDS Snapshot (validates backup works)
source scripts/00-setup.sh

SNAPSHOT_ID="$APP_NAME-snapshot-$(date +%Y%m%d-%H%M)"

echo "Creating manual RDS snapshot: $SNAPSHOT_ID"
aws rds create-db-snapshot \
  --db-instance-identifier "$APP_NAME-db" \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --region $AWS_REGION

echo "Waiting for snapshot to complete..."
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --region $AWS_REGION

echo "Snapshot complete: $SNAPSHOT_ID"

echo "Listing all snapshots for this instance:"
aws rds describe-db-snapshots \
  --db-instance-identifier "$APP_NAME-db" \
  --region $AWS_REGION \
  --query 'DBSnapshots[].{ID:DBSnapshotIdentifier,Status:Status,Time:SnapshotCreateTime}' \
  --output table
