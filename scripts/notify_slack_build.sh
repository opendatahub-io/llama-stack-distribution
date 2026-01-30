#!/usr/bin/env bash
# Notify Slack when a container image is successfully pushed to a registry.
# Used by GitHub Actions; can be run locally for testing with --preview.
#
# Required env vars: REGISTRY, IMAGE_NAME, IMAGE_TAG, BRANCH, TRIGGER,
#   COMMIT_URL, COMMIT_SHA, WORKFLOW_URL
# Optional: BUILD_LABEL (e.g. "RHOAI v3.4.0"), IMAGE_DIGEST (sha256:...), BUILD_NAME (e.g. run id).
# Optional (at least one for sending): SLACK_WEBHOOK_URL or SLACK_WEBHOOK_URLS
#   SLACK_WEBHOOK_URL  — single webhook URL (legacy).
#   SLACK_WEBHOOK_URLS — comma-separated list of webhook URLs. Same message is
#                        sent to each. Use this to add channels or registry-specific
#                        hooks without changing the script; set in workflow from
#                        one or more secrets.
#   If both are set, SLACK_WEBHOOK_URLS wins. If neither is set, skip send (exit 0).
#
# Usage:
#   ./scripts/notify_slack_build.sh           # send to all configured webhooks
#   ./scripts/notify_slack_build.sh --preview # print message to stdout, do not send

set -euo pipefail

PREVIEW=false
if [[ "${1:-}" == "--preview" ]]; then
  PREVIEW=true
fi

# Required inputs (from workflow env or caller)
: "${REGISTRY:?REGISTRY is required}"
: "${IMAGE_NAME:?IMAGE_NAME is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${BRANCH:?BRANCH is required}"
: "${TRIGGER:?TRIGGER is required}"
: "${COMMIT_URL:?COMMIT_URL is required}"
: "${COMMIT_SHA:?COMMIT_SHA is required}"
: "${WORKFLOW_URL:?WORKFLOW_URL is required}"

COMMIT_SHA_SHORT="${COMMIT_SHA:0:7}"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# Optional: BUILD_LABEL (e.g. "RHOAI v3.4.0"), IMAGE_DIGEST (sha256:...), BUILD_NAME (e.g. run id or job name)
BUILD_LABEL="${BUILD_LABEL:-Llama Stack}"
IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"
[[ -n "${IMAGE_DIGEST:-}" ]] && IMAGE_REF="${IMAGE_REF}@${IMAGE_DIGEST}"
BUILD_NAME="${BUILD_NAME:-$WORKFLOW_URL}"

build_message() {
  # Plain format matching RHOAI devops style
  printf '%s\n%s\n%s\n%s\n' \
    ":github-1: *New image is available for ${BUILD_LABEL}* - [${TIMESTAMP}]" \
    "Image: ${IMAGE_REF}" \
    "Commit: ${COMMIT_SHA_SHORT}" \
    "Build: ${BUILD_NAME}"
}

if [[ "$PREVIEW" == true ]]; then
  echo "::group::Slack message preview (not sent)"
  build_message
  echo "::endgroup::"
  exit 0
fi

# Collect webhook URL(s): SLACK_WEBHOOK_URLS (comma-separated) or SLACK_WEBHOOK_URL (single)
WEBHOOK_URLS=""
if [[ -n "${SLACK_WEBHOOK_URLS:-}" ]]; then
  WEBHOOK_URLS="${SLACK_WEBHOOK_URLS}"
elif [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  WEBHOOK_URLS="${SLACK_WEBHOOK_URL}"
fi

if [[ -z "$WEBHOOK_URLS" ]]; then
  echo "Slack webhook secret not configured (e.g. fork), skipping notification"
  exit 0
fi

normalize_url() {
  local url
  url="$(echo "$1" | xargs)"
  if [[ -z "$url" ]]; then
    return
  fi
  if [[ "$url" != http* ]]; then
    url="https://hooks.slack.com/${url#/}"
  fi
  echo "$url"
}

TEXT=$(build_message)
# Colored attachment (left border #46567f); blocks with mrkdwn for links/bold/code
# See: https://docs.slack.dev/messaging/formatting-message-text/#when-to-use-attachments
PAYLOAD=$(jq -n --arg text "$TEXT" '{
  attachments: [
    {
      color: "#46567f",
      blocks: [
        {
          type: "section",
          text: { type: "mrkdwn", text: $text }
        }
      ]
    }
  ]
}')
SENT=0
while IFS= read -r -d ',' url_raw || break; do
  url=$(normalize_url "$url_raw")
  [[ -z "$url" ]] && continue
  if curl -sf -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$url"; then
    ((SENT++)) || true
  else
    echo "Slack notification failed for one webhook" >&2
    exit 1
  fi
done <<< "${WEBHOOK_URLS},"

if [[ $SENT -gt 0 ]]; then
  echo "Slack notification sent to ${SENT} channel(s)"
fi
