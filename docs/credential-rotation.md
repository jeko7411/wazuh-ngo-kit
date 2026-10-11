# Replacing default credentials (Docker, single-node)

Manual procedure used on Wazuh 4.14.8. It is deliberately not automated: a typing error locks components out, so each step is verified before the next one. Status of each part: `admin`, `wazuh-wui`, `kibanaserver` and the enrolment password were applied on the reference server; the status of the API user `wazuh` is in CHANGELOG.md.

Default credentials of a fresh install (public, documented by Wazuh): indexer users `admin` and `kibanaserver`; API users `wazuh-wui` and `wazuh`.

Password rules
- API users: 8 to 64 characters with an uppercase letter, a lowercase letter, a number and a symbol. If the rule is not met the manager does not start.
- Use only letters, digits and `. - _ * + !`. The characters `$ " ' \ # & %` and spaces break YAML, Docker Compose or JSON.
- If a password contains `$` it must be doubled in `docker-compose.yml`.
- Type passwords with `read -rs` so they do not reach the shell history, and never paste them into tickets, chats or commits.

Run everything from `wazuh-docker/single-node`.

## A. Indexer user `admin` (validated)

1. Back up and log out of the dashboard.
   ```bash
   mkdir -p ~/wazuh-backup/pw-change
   cp docker-compose.yml config/wazuh_indexer/internal_users.yml ~/wazuh-backup/pw-change/
   docker compose down
   ```
2. Generate the hash (the tool asks for the password):
   ```bash
   docker run --rm -ti wazuh/wazuh-indexer:<VERSION> bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh
   ```
3. Put the hash, quoted, in the `admin` block of `config/wazuh_indexer/internal_users.yml`.
4. Replace the old password in `docker-compose.yml` (variable `INDEXER_PASSWORD`, in the manager and dashboard services). Ask for it twice:
   ```bash
   read -rs -p "New admin password: " P1; echo
   read -rs -p "Repeat: " P2; echo
   if [ "$P1" = "$P2" ]; then sed -i "s|SecretPassword|${P1}|g" docker-compose.yml && echo "Changed"; else echo "Mismatch, nothing changed"; fi
   unset P1 P2
   grep -c SecretPassword docker-compose.yml   # must print 0
   ```
5. Start the stack and wait until the indexer answers (it still has the old password until the next step):
   ```bash
   docker compose up -d
   ```
6. Apply the security configuration inside the indexer container:
   ```bash
   docker exec single-node-wazuh.indexer-1 bash -c '
   export INSTALLATION_DIR=/usr/share/wazuh-indexer
   export CONFIG_DIR=$INSTALLATION_DIR/config
   export JAVA_HOME=$INSTALLATION_DIR/jdk
   bash $INSTALLATION_DIR/plugins/opensearch-security/tools/securityadmin.sh \
     -cd $CONFIG_DIR/opensearch-security/ -nhnv \
     -cacert $CONFIG_DIR/certs/root-ca.pem \
     -cert $CONFIG_DIR/certs/admin.pem \
     -key $CONFIG_DIR/certs/admin-key.pem \
     -p 9200 -icl'
   ```
   It must end with `Done with success`. The container name depends on the Compose version (`single-node-wazuh.indexer-1` with Compose v2).
7. Verify with the new password:
   ```bash
   curl -sk -u admin "https://localhost:9200/_cluster/health?pretty" | grep status
   docker compose exec wazuh.manager filebeat test output     # must end with: talk to server... OK
   ```
   The procedure reapplies `internal_users.yml`: users created by hand in the dashboard and missing from that file are deleted.

## B. API user `wazuh-wui` (validated, with a caveat)

Changing `API_PASSWORD` in `docker-compose.yml` and the password in `config/wazuh_dashboard/wazuh.yml` is not enough in an existing deployment: the manager keeps the stored API password. Change it through the API and make the three places agree.

```bash
TOKEN=$(curl -sk -u wazuh-wui -X POST "https://localhost:55000/security/user/authenticate?raw=true")
curl -sk -H "Authorization: Bearer $TOKEN" "https://localhost:55000/security/users?pretty=true" | grep -E '"id"|"username"'
read -rs -p "New API password: " P1; echo
read -rs -p "Repeat: " P2; echo
if [ "$P1" = "$P2" ]; then
  curl -sk -X PUT "https://localhost:55000/security/users/2" -H "Authorization: Bearer $TOKEN" \
       -H "Content-Type: application/json" -d "{\"password\":\"$P1\"}"
else
  echo "Mismatch, nothing changed"
fi
unset P1 P2 TOKEN
```

The user id (2 in our deployment) comes from the listing. Then use the same value in `API_PASSWORD` (manager and dashboard services of `docker-compose.yml`) and in the `password:` field of `config/wazuh_dashboard/wazuh.yml`, and restart the dashboard.

Always ask the password twice and check that the value stored in `wazuh.yml` authenticates:

```bash
PW=$(grep -m1 'password:' config/wazuh_dashboard/wazuh.yml | sed -E 's/.*password:[[:space:]]*"?([^"]*)"?.*/\1/')
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -u "wazuh-wui:$PW" -X POST "https://localhost:55000/security/user/authenticate?raw=true"   # 200 expected
unset PW
```

## C. Other credentials

### C1. Indexer user `kibanaserver` (applied and verified on 2026-10-10)
Same mechanism as section A, with three differences:
- Put the hash in the `kibanaserver` block of `internal_users.yml`; put the **plain password** (not the hash) in the `DASHBOARD_PASSWORD` variable of the dashboard service.
- Change only that line, for example `sed -i "s|^\( *- DASHBOARD_PASSWORD=\).*|\1${P1}|" docker-compose.yml` after validating the password with `^[A-Za-z0-9.*+!_-]{8,64}$`.
- Recreate the stack (`docker compose down`, `up -d`), run `securityadmin.sh` as in section A, then `docker compose up -d --force-recreate wazuh.dashboard` (a plain `restart` does not re-read the compose file).

Verify: the new password works against `/_plugins/_security/authinfo`, the default returns HTTP 401, and the dashboard log has no authentication errors.

### C2. Agent enrolment password (applied and verified on 2026-10-10)
1. In `config/wazuh_cluster/wazuh_manager.conf` set `<use_password>yes</use_password>` in the `<auth>` block.
2. Write the password inside the manager (not in the shell history):
   ```bash
   read -rs -p "Enrolment password: " P1; echo
   printf '%s' "$P1" | docker exec -i <manager-container> bash -c 'cat > /var/ossec/etc/authd.pass && chown root:wazuh /var/ossec/etc/authd.pass && chmod 640 /var/ossec/etc/authd.pass'
   unset P1
   ```
3. `docker compose restart wazuh.manager` and check `grep use_password /var/ossec/etc/ossec.conf` inside the container.
4. Verify with the registration port itself (agents already enrolled are not affected):
   ```bash
   printf "OSSEC A:'test-no-password'\n" | timeout 8 openssl s_client -connect 127.0.0.1:1515 -quiet 2>/dev/null          # must NOT return OSSEC K:
   printf "OSSEC PASS: %s OSSEC A:'test-with-password'\n" "$PASS" | timeout 8 openssl s_client -connect 127.0.0.1:1515 -quiet 2>/dev/null   # must return OSSEC K:
   ```
   Remove the test agents afterwards (`manage_agents -r <ID>`). Mask the returned key if you save the output.
5. New agents are installed with `WAZUH_REGISTRATION_PASSWORD='...'` added to the `msiexec` line.

### C3. API user `wazuh`
A fresh install ships this API user with the default password. Change it with the call of section B, using its own user id (list users with the token and read the id), and check that the default password now returns HTTP 401:

```bash
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -u wazuh:wazuh -X POST "https://localhost:55000/security/user/authenticate?raw=true"   # 401 expected after the change
```
