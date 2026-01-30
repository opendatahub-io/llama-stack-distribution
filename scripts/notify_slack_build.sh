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
#   NOTIFY_FAILURE=1 — send a "Build failed" message (red attachment); same webhook(s).
#
# Usage:
#   ./scripts/notify_slack_build.sh           # send success to all configured webhooks
#   NOTIFY_FAILURE=1 ./scripts/notify_slack_build.sh  # send failure message
#   ./scripts/notify_slack_build.sh --preview # print message to stdout, do not send

set -euo pipefail

PREVIEW=false
NOTIFY_FAILURE="${NOTIFY_FAILURE:-0}"
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
# Optional: BUILD_LABEL (e.g. "RHOAI v3.4.0"), IMAGE_DIGEST (sha256:...), WORKFLOW_RUN_URL (e.g. github.com/.../actions/runs/...)
BUILD_LABEL="${BUILD_LABEL:-Llama Stack}"
IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"
[[ -n "${IMAGE_DIGEST:-}" ]] && IMAGE_REF="${IMAGE_REF}@${IMAGE_DIGEST}"
WORKFLOW_RUN_URL="${WORKFLOW_URL}"

build_message() {
  # Plain format matching RHOAI devops style; failure vs success headline
  if [[ "${NOTIFY_FAILURE}" == "1" ]]; then
    printf '%s\n%s\n%s\n%s\n' \
      "🔴 *Build failed for ${BUILD_LABEL}* - [${TIMESTAMP}]" \
      "Image: ${IMAGE_REF}" \
      "Commit: ${COMMIT_SHA_SHORT}" \
      "<${WORKFLOW_RUN_URL}|View workflow run>"
  else
    printf '%s\n%s\n%s\n%s\n' \
      "🟢 *New image is available for ${BUILD_LABEL}* - [${TIMESTAMP}]" \
      "Image: ${IMAGE_REF}" \
      "Commit: ${COMMIT_SHA_SHORT}" \
      "<${WORKFLOW_RUN_URL}|View workflow run>"
  fi
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
# Attachment color: blue for success, red for failure
if [[ "${NOTIFY_FAILURE}" == "1" ]]; then
  ATTACHMENT_COLOR="#d00000"
else
  ATTACHMENT_COLOR="#46567f"
fi
PAYLOAD=$(jq -n --arg text "$TEXT" --arg color "$ATTACHMENT_COLOR" '{
  attachments: [
    {
      color: $color,
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
