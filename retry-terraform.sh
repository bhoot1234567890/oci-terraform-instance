#!/bin/bash

# OCI Terraform Retry Script
# Retries terraform apply until successful or max attempts reached
# A1 instances often become available when others delete their instances

LOG_FILE="terraform-retry.log"
ATTEMPT=0
MAX_ATTEMPTS=${MAX_ATTEMPTS:-0}  # 0 = unlimited

notify_success() {
    # macOS notification
    if command -v osascript &> /dev/null; then
        osascript -e 'display notification "OCI Instance Created!" with title "Terraform" sound name "Glass"'
    fi
    # Linux notification (if available)
    if command -v notify-send &> /dev/null; then
        notify-send "Terraform" "OCI Instance Created!"
    fi
}

echo "Starting OCI instance provisioning retry loop..."
echo "Logs will be written to: $LOG_FILE"
echo "Max attempts: ${MAX_ATTEMPTS:-unlimited}"
echo "Press Ctrl+C to stop"
echo "----------------------------------------"

while true; do
    ATTEMPT=$((ATTEMPT + 1))
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$TIMESTAMP] Attempt #$ATTEMPT" | tee -a "$LOG_FILE"

    # Run terraform apply and capture output
    OUTPUT=$(terraform apply -auto-approve 2>&1)
    EXIT_CODE=$?

    echo "$OUTPUT" | tee -a "$LOG_FILE"

    # Check for actual success (terraform exit code 0 AND no capacity error)
    if [ $EXIT_CODE -eq 0 ] && ! echo "$OUTPUT" | grep -q "Out of host capacity"; then
        echo "[$TIMESTAMP] SUCCESS! Instance created on attempt #$ATTEMPT" | tee -a "$LOG_FILE"
        echo "----------------------------------------"
        echo "Instance provisioned successfully!"
        notify_success
        terraform output
        exit 0
    fi

    # Check max attempts
    if [ "$MAX_ATTEMPTS" -gt 0 ] && [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
        echo "[$TIMESTAMP] Reached max attempts ($MAX_ATTEMPTS). Exiting." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Random jitter (0-15 seconds) to avoid sync with others retrying
    JITTER=$((RANDOM % 15))
    SLEEP_TIME=$((60 + JITTER))

    echo "[$TIMESTAMP] Attempt #$ATTEMPT failed. Retrying in ${SLEEP_TIME}s (jitter: ${JITTER}s)..." | tee -a "$LOG_FILE"
    echo "----------------------------------------"
    sleep "$SLEEP_TIME"
done
