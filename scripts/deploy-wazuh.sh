#!/usr/bin/env bash
# Deploy a pinned Wazuh single-node (Docker) stack from the official wazuh-docker repository.
# Fresh installs only. For upgrades follow the official wazuh-docker guide.
# Usage: WAZUH_VERSION=4.14.8 INSTALL_DIR=$HOME/wazuh-docker ./deploy-wazuh.sh
set -euo pipefail

WAZUH_VERSION="${WAZUH_VERSION:-4.14.8}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/wazuh-docker}"
INDEXER_USER="${INDEXER_USER:-admin}"
INDEXER_PASSWORD="${INDEXER_PASSWORD:-SecretPassword}"   # default of a fresh install; rotate it afterwards
WAIT_SECONDS="${WAIT_SECONDS:-600}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v git    >/dev/null || die "git is required"
command -v curl   >/dev/null || die "curl is required"
command -v docker >/dev/null || die "docker is required"

DOCKER="docker"
docker info >/dev/null 2>&1 || DOCKER="sudo docker"
$DOCKER compose version >/dev/null 2>&1 || die "Docker Compose v2 plugin not found (Ubuntu 24.04: apt install docker-compose-v2)"

MAP_COUNT="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
if [ "$MAP_COUNT" -lt 262144 ]; then
  die "vm.max_map_count is $MAP_COUNT (needs >= 262144). Run: sudo sysctl -w vm.max_map_count=262144 and persist it in /etc/sysctl.d/"
fi

[ ! -e "$INSTALL_DIR" ] || die "$INSTALL_DIR already exists; this script is for fresh installs"

log "Cloning wazuh-docker v${WAZUH_VERSION}"
git clone --quiet --branch "v${WAZUH_VERSION}" --depth 1 https://github.com/wazuh/wazuh-docker.git "$INSTALL_DIR"
cd "$INSTALL_DIR/single-node"

log "Binding the indexer and API ports to localhost"
bash "$SCRIPT_DIR/harden-ports.sh" --dir "$PWD"

log "Generating certificates"
$DOCKER compose -f generate-indexer-certs.yml run --rm generator

log "Starting the stack"
$DOCKER compose up -d

log "Waiting for the indexer (up to ${WAIT_SECONDS}s)"
start=$SECONDS
until curl -sk -u "${INDEXER_USER}:${INDEXER_PASSWORD}" "https://localhost:9200/_cluster/health" | grep -Eq '"status":"(green|yellow)"'; do
  if [ $((SECONDS - start)) -ge "$WAIT_SECONDS" ]; then
    die "the indexer did not become healthy in time. Check: $DOCKER compose logs wazuh.indexer"
  fi
  sleep 10
done

log "Deployed versions"
$DOCKER compose exec -T wazuh.manager /var/ossec/bin/wazuh-control info | grep -E 'VERSION|REVISION' || true
$DOCKER compose ps

cat <<'EOF'

Next steps (see README.md)
  1. Replace the default credentials and enable the agent enrolment password (docs/credential-rotation.md).
  2. Create the agent groups:  docker compose exec wazuh.manager /var/ossec/bin/agent_groups -a -g GROUP_NAME -q
  3. Load config/rules/CR-RULE.xml and the group agent.conf files from config/groups/.
  4. Enrol the agents.
EOF
