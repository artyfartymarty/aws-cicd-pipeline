#!/usr/bin/env bash
# Start/stop the self-hosted runner so you only pay for it while you use it.
# Stopped, it costs about $0.64/month (the 8 GB disk); its public IP is released.
# Usage: scripts/runner-power.sh start|stop|status
set -euo pipefail

PROJECT="${PROJECT:-cicd-lab}"
REGION="${AWS_REGION:-us-east-1}"

ID="$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=${PROJECT}-runner" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"
if [ -z "$ID" ] || [ "$ID" = "None" ]; then
  echo "No runner instance found (tag Name=${PROJECT}-runner)." >&2
  exit 1
fi

case "${1:-status}" in
  start)  aws ec2 start-instances --region "$REGION" --instance-ids "$ID" >/dev/null
          aws ec2 wait instance-running --region "$REGION" --instance-ids "$ID"
          echo "Runner $ID is running. It shows as Idle in GitHub within a minute or two." ;;
  stop)   aws ec2 stop-instances --region "$REGION" --instance-ids "$ID" >/dev/null
          echo "Runner $ID is stopping." ;;
  status) aws ec2 describe-instances --region "$REGION" --instance-ids "$ID" \
            --query 'Reservations[0].Instances[0].[InstanceId,State.Name,InstanceType,InstanceLifecycle]' --output text ;;
  *) echo "usage: $0 start|stop|status" >&2; exit 2 ;;
esac
