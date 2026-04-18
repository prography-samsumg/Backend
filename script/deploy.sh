#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE_NAME:?IMAGE_NAME is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"

ENV_FILE="${ENV_FILE:-$HOME/prography/.env}"
CONTAINER_NAME="${CONTAINER_NAME:-prography-backend}"
HOST_PORT="${HOST_PORT:-8080}"
CONTAINER_PORT="${CONTAINER_PORT:-8080}"
DOCKER_NETWORK="${DOCKER_NETWORK:-}"
SPRING_PROFILES_ACTIVE="${SPRING_PROFILES_ACTIVE:-prod}"
GHCR_USERNAME="${GHCR_USERNAME:-}"
GHCR_TOKEN="${GHCR_TOKEN:-}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://localhost:${HOST_PORT}/actuator/health}"
HEALTHCHECK_TIMEOUT="${HEALTHCHECK_TIMEOUT:-180}"
HEALTHCHECK_INTERVAL="${HEALTHCHECK_INTERVAL:-5}"
TARGET_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed."
  exit 1
fi

if [ -f "${ENV_FILE}" ]; then
  echo "[deploy] Use env file: ${ENV_FILE}"
else
  echo "[deploy] Env file not found, proceeding without --env-file: ${ENV_FILE}"
fi

get_current_image() {
  sudo docker inspect -f '{{.Config.Image}}' "${CONTAINER_NAME}" 2>/dev/null || true
}

remove_container_if_exists() {
  if sudo docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    echo "[deploy] Removing existing container: ${CONTAINER_NAME}"
    sudo docker rm -f "${CONTAINER_NAME}" >/dev/null
  fi
}

run_container() {
  local image_ref="$1"
  local -a docker_run_args

  docker_run_args=(
    run
    -d
    --name "${CONTAINER_NAME}"
    --restart unless-stopped
    -p "${HOST_PORT}:${CONTAINER_PORT}"
    -e "SPRING_PROFILES_ACTIVE=${SPRING_PROFILES_ACTIVE}"
  )

  if [ -f "${ENV_FILE}" ]; then
    docker_run_args+=(--env-file "${ENV_FILE}")
  fi

  if [ -n "${DOCKER_NETWORK}" ]; then
    docker_run_args+=(--network "${DOCKER_NETWORK}")
  fi

  docker_run_args+=("${image_ref}")

  echo "[deploy] Run container ${CONTAINER_NAME} from ${image_ref}"
  sudo docker "${docker_run_args[@]}"
}

wait_for_health() {
  if [ -z "${HEALTHCHECK_URL}" ]; then
    echo "[deploy] HEALTHCHECK_URL is empty, skipping health check."
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "[deploy] curl not found, skipping health check."
    return 0
  fi

  echo "[deploy] Waiting for health check: ${HEALTHCHECK_URL}"
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    if curl -fsS "${HEALTHCHECK_URL}" >/dev/null; then
      echo "[deploy] Health check passed."
      return 0
    fi

    local now_ts elapsed
    now_ts="$(date +%s)"
    elapsed=$((now_ts - start_ts))
    if [ "${elapsed}" -ge "${HEALTHCHECK_TIMEOUT}" ]; then
      echo "[deploy] Health check timed out after ${HEALTHCHECK_TIMEOUT}s."
      return 1
    fi

    sleep "${HEALTHCHECK_INTERVAL}"
  done
}

rollback() {
  local rollback_image="$1"

  if [ -z "${rollback_image}" ] || [ "${rollback_image}" = "${TARGET_IMAGE}" ]; then
    echo "[deploy] No rollback target available."
    return 1
  fi

  echo "[deploy] Rolling back to ${rollback_image}"
  remove_container_if_exists
  run_container "${rollback_image}"
}

if [ -n "${GHCR_USERNAME}" ] && [ -n "${GHCR_TOKEN}" ]; then
  echo "[deploy] Login to ghcr.io as ${GHCR_USERNAME}"
  echo "${GHCR_TOKEN}" | sudo docker login ghcr.io -u "${GHCR_USERNAME}" --password-stdin
else
  echo "[deploy] GHCR credentials not provided, proceeding without docker login"
fi

PREV_IMAGE="$(get_current_image || true)"
if [ -n "${PREV_IMAGE}" ]; then
  echo "[deploy] Previous image detected: ${PREV_IMAGE}"
else
  echo "[deploy] No previous image detected (first deploy or container missing)"
fi

echo "[deploy] Pull image: ${TARGET_IMAGE}"
sudo docker pull "${TARGET_IMAGE}"

remove_container_if_exists

if ! run_container "${TARGET_IMAGE}"; then
  echo "[deploy] Deploy failed."
  rollback "${PREV_IMAGE}" || true
  exit 1
fi

if ! wait_for_health; then
  echo "[deploy] Health check failed."
  sudo docker logs --tail 100 "${CONTAINER_NAME}" || true
  rollback "${PREV_IMAGE}" || true
  exit 1
fi

echo "[deploy] Cleanup dangling images"
sudo docker image prune -f >/dev/null 2>&1 || true

echo "[deploy] Done"
