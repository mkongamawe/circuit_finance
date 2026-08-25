#!/bin/bash
set -e
/usr/local/bin/write-renviron.sh
exec "$@"