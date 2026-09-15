#!/usr/bin/env bash

set -euo pipefail

sudo pg_ctlcluster 16 main start

for _ in $(seq 1 30); do
  pg_isready --host 127.0.0.1 --port 5432 --dbname postgres >/dev/null && break
  sleep 1
done

pg_isready --host 127.0.0.1 --port 5432 --dbname postgres >/dev/null
exec tail -f /dev/null
