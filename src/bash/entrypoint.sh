#!/bin/bash
set -euo pipefail

# Shiny Server spawns each app as a lower-privileged user (default: `shiny`)
# via `su --login`, which wipes almost all inherited environment variables
# for security. That means DB_* vars set via `docker-compose environment:`
# / `env_file:` never reach the R process, even though they're correctly
# present in this (root) entrypoint process.
#
# Fix: write them to the shiny user's own .Renviron. R reads that file
# directly at startup — independent of whatever the login shell stripped —
# so this survives the su step cleanly.

SHINY_HOME=$(getent passwd shiny | cut -d: -f6)

{
  echo "CIRCUIT_DB_HOST=${CIRCUIT_DB_HOST:-}"
  echo "CIRCUIT_DB_PORT=${CIRCUIT_DB_PORT:-}"
  echo "CIRCUIT_DB_NAME=${CIRCUIT_DB_NAME:-}"
  echo "CIRCUIT_DB_USER=${CIRCUIT_DB_USER:-}"
  echo "CIRCUIT_DB_PASS=${CIRCUIT_DB_PASS:-}"
} > "${SHINY_HOME}/.Renviron"

chown shiny:shiny "${SHINY_HOME}/.Renviron"
chmod 600 "${SHINY_HOME}/.Renviron"

exec "$@"