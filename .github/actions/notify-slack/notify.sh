#!/usr/bin/env bash
# Send a Slack message via incoming webhook.
# Used by GitHub Actions workflows.
#
# Args:    $1 TEXT  (required) — the Slack mrkdwn message (or --preview)
#          $2 COLOR (optional) — attachment color (default "#46567f")
# Env:     SLACK_WEBHOOK_URL (single) or SLACK_WEBHOOK_URLS (comma-separated)
# Flags:   --preview as $1 — print message to stdout, do not send
#
# Usage:
#   ./notify.sh "msg"                        # send message
#   ./notify.sh "msg" "#d00000"              # send message with custom color
#   ./notify.sh --preview "msg"              # print message, do not send

set -euo pipefail

PREVIEW=false
if [[ "${1:-}" == "--preview" ]]; then
  PREVIEW=true
  shift
fi

TEXT="${1:?Usage: $0 [--preview] TEXT [COLOR]}"
COLOR="${2:-#46567f}"

if [[ "$PREVIEW" == true ]]; then
  echo "::group::Slack message preview (not sent)"
  echo "$TEXT"
  echo "::endgroup::"
  exit 0
fi

# Collect webhook URL(s)
WEBHOOK_URLS="${SLACK_WEBHOOK_URLS:-${SLACK_WEBHOOK_URL:-}}"

if [[ -z "$WEBHOOK_URLS" ]]; then
  echo "Slack webhook not configured, skipping notification"
  exit 0
fi

PAYLOAD=$(jq -n --arg text "$TEXT" --arg color "$COLOR" '{
  attachments: [{
    color: $color,
    blocks: [{ type: "section", text: { type: "mrkdwn", text: $text } }]
  }]
}')

SENT=0
FAILED_COUNT=0
IFS=',' read -ra URLS <<< "$WEBHOOK_URLS"
for url in "${URLS[@]}"; do
  read -r url <<< "$url"  # trim whitespace
  [[ -z "$url" ]] && continue
  if [[ "$url" != https://* ]]; then
    echo "Skipping invalid webhook URL (must start with https://)" >&2
    ((FAILED_COUNT++)) || true
    continue
  fi
  if curl -sf --connect-timeout 5 --max-time 10 -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$url"; then
    ((SENT++)) || true
  else
    echo "Slack notification failed for webhook" >&2
    ((FAILED_COUNT++)) || true
  fi
done

[[ $SENT -gt 0 ]] && echo "Slack notification sent to ${SENT} channel(s)"
[[ $FAILED_COUNT -gt 0 ]] && echo "${FAILED_COUNT} webhook(s) failed" >&2
if [[ $FAILED_COUNT -gt 0 ]]; then
  exit 1
fi
