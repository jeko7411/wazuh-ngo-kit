#!/usr/bin/env bash
# Publish the Wazuh indexer (9200) and API (55000) on 127.0.0.1 only, in the single-node docker-compose.yml.
# Agent ports (1514/1515), syslog (514/udp) and the dashboard (443) are not changed.
# Usage: harden-ports.sh --dir <path-to-wazuh-docker/single-node> [--apply]
set -euo pipefail

usage() { sed -n '2,4p' "$0"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

DIR=""
APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)     [ $# -ge 2 ] || die "--dir needs a value"; DIR="$2"; shift 2 ;;
    --apply)   APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         die "unknown option: $1" ;;
  esac
done
[ -n "$DIR" ] || { usage; die "--dir is required"; }

FILE="$DIR/docker-compose.yml"
[ -f "$FILE" ] || die "$FILE not found"

BACKUP="$FILE.pre-ports.$(date +%Y%m%d%H%M%S)"
cp "$FILE" "$BACKUP"
echo "Backup: $BACKUP"

sed -i -E \
  -e 's|^([[:space:]]*-[[:space:]]*)"55000:55000"|\1"127.0.0.1:55000:55000"|' \
  -e 's|^([[:space:]]*-[[:space:]]*)"9200:9200"|\1"127.0.0.1:9200:9200"|' "$FILE"

grep -q '"127.0.0.1:55000:55000"' "$FILE" || die "API port line not found or not changed. Restore with: cp $BACKUP $FILE"
grep -q '"127.0.0.1:9200:9200"' "$FILE"   || die "indexer port line not found or not changed. Restore with: cp $BACKUP $FILE"

echo "Resulting port mappings:"
grep -n -E '"(127\.0\.0\.1:)?(9200|55000|1514|1515):' "$FILE" || true

if [ "$APPLY" -eq 1 ]; then
  DOCKER="docker"
  docker info >/dev/null 2>&1 || DOCKER="sudo docker"
  (cd "$DIR" && $DOCKER compose up -d)
else
  echo "Not applied. Recreate the containers with: (cd $DIR && docker compose up -d)"
fi
