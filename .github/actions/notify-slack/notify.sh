#!/usr/bin/env bash
# Notify Slack about build status (success or failure).
# Used by GitHub Actions workflow.
#
# Required: COMMIT_SHA, WORKFLOW_URL. For success: IMAGE_NAME, IMAGE_TAG.
# Optional: SLACK_WEBHOOK_URL (single) or SLACK_WEBHOOK_URLS (comma-separated)
#           NOTIFY_FAILURE=1 — failure message (IMAGE_NAME/IMAGE_TAG optional)
#
# Usage:
#   ./notify.sh              # send success notification
#   NOTIFY_FAILURE=1 ./notify.sh  # send failure notification
#   ./notify.sh --preview    # print message to stdout, do not send

set -euo pipefail

PREVIEW=false
NOTIFY_FAILURE="${NOTIFY_FAILURE:-0}"
[[ "${1:-}" == "--preview" ]] && PREVIEW=true

# Required inputs (IMAGE_NAME/IMAGE_TAG required for success only)
: "${COMMIT_SHA:?COMMIT_SHA is required}"
: "${WORKFLOW_URL:?WORKFLOW_URL is required}"
if [[ "${NOTIFY_FAILURE}" != "1" ]]; then
  : "${IMAGE_NAME:?IMAGE_NAME is required for success notification}"
  : "${IMAGE_TAG:?IMAGE_TAG is required for success notification}"
fi

COMMIT_SHA_SHORT="${COMMIT_SHA:0:7}"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
IMAGE_REF=""
[[ -n "${IMAGE_NAME:-}" && -n "${IMAGE_TAG:-}" ]] && IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"

build_message() {
  if [[ "${NOTIFY_FAILURE}" == "1" ]]; then
    printf '%s\n%s\n%s\n' \
      ":failed: *Build failed for Llama Stack* - [${TIMESTAMP}]" \
      "Commit: ${COMMIT_SHA_SHORT}" \
      "<${WORKFLOW_URL}|View workflow run>"
  else
    printf '%s\n%s\n%s\n%s\n' \
      ":greenchecked: *New image is available for Llama Stack* - [${TIMESTAMP}]" \
      "Image: ${IMAGE_REF}" \
      "Commit: ${COMMIT_SHA_SHORT}" \
      "<${WORKFLOW_URL}|View workflow run>"
  fi
}

if [[ "$PREVIEW" == true ]]; then
  echo "::group::Slack message preview (not sent)"
  build_message
  echo "::endgroup::"
  exit 0
fi

# Collect webhook URL(s)
WEBHOOK_URLS="${SLACK_WEBHOOK_URLS:-${SLACK_WEBHOOK_URL:-}}"

if [[ -z "$WEBHOOK_URLS" ]]; then
  echo "Slack webhook not configured, skipping notification"
  exit 0
fi

TEXT=$(build_message)
COLOR=$([[ "${NOTIFY_FAILURE}" == "1" ]] && echo "#d00000" || echo "#46567f")
PAYLOAD=$(jq -n --arg text "$TEXT" --arg color "$COLOR" '{
  attachments: [{
    color: $color,
    blocks: [{ type: "section", text: { type: "mrkdwn", text: $text } }]
  }]
}')

SENT=0
IFS=',' read -ra URLS <<< "$WEBHOOK_URLS"
for url in "${URLS[@]}"; do
  url=$(echo "$url" | xargs)  # trim whitespace
  [[ -z "$url" ]] && continue
  [[ "$url" != http* ]] && url="https://hooks.slack.com/${url#/}"
  if curl -sf -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$url"; then
    ((SENT++)) || true
  else
    echo "Slack notification failed for webhook" >&2
    exit 1
  fi
done

[[ $SENT -gt 0 ]] && echo "Slack notification sent to ${SENT} channel(s)"
