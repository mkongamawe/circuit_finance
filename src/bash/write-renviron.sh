#!/bin/bash
{
  echo "CIRCUIT_DB_HOST=${CIRCUIT_DB_HOST}"
  echo "CIRCUIT_DB_PORT=${CIRCUIT_DB_PORT}"
  echo "CIRCUIT_DB_NAME=${CIRCUIT_DB_NAME}"
  echo "CIRCUIT_DB_USER=${CIRCUIT_DB_USER}"
  echo "CIRCUIT_DB_PASS=${CIRCUIT_DB_PASS}"
} >> /usr/local/lib/R/etc/Renviron.site