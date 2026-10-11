# Kit de despliegue y reglas FIM de Wazuh para una ONG (Docker, un solo nodo)

Material técnico del artículo *Diseño de un marco de trabajo eficiente y sostenible para la resiliencia cibernética en ONG ecuatorianas de bajos recursos*. Permite repetir el despliegue de Wazuh 4.14.8 (Docker, un solo nodo) que monitorea equipos Windows, con las reglas personalizadas de integridad de archivos (FIM), la configuración por grupos y el script de validación usados en el estudio de caso.

Los nombres de usuario, carpetas y aplicaciones de la institución están reemplazados por marcadores (`USER1`, `CRITICAL_FOLDER_1`, `APP_DIR_1`, ...). Los scripts y los documentos de procedimiento de credenciales están escritos en inglés; el resto, en español.

## 1. Contenido

| Ruta | Para qué sirve |
|---|---|
| `scripts/deploy-wazuh.sh` | Instalación nueva de una versión fija de Wazuh desde el repositorio oficial `wazuh-docker` |
| `scripts/harden-ports.sh` | Publica el indexador (9200) y la API (55000) solo en `127.0.0.1` |
| `scripts/Test-FIM.ps1` | Genera eventos de archivos sintéticos en un equipo Windows para validar las reglas |
| `config/rules/CR-RULE.xml` | Reglas personalizadas 100005, 100006, 100008 y 100009, tal como están desplegadas |
| `config/groups/CR-*.agent.conf` | `agent.conf` de los cuatro grupos (Salud, Financiero, Administrativo, Infraestructura) |
| `docs/credential-rotation.md` | Procedimiento manual para reemplazar las credenciales por defecto y activar la contraseña de registro de agentes |
| `docs/operacion.md` | Procedimiento operativo mínimo (corte de energía, comprobaciones, alta de equipos) |
| `CHANGELOG.md` | Qué se verificó, qué se reportó y qué queda pendiente |

## 2. Entorno de referencia

| Elemento | Versión |
|---|---|
| Sistema operativo del servidor | Ubuntu Server 24.04.4 LTS |
| Docker Engine / Compose | 29.1.3 / v2 2.40.3 |
| Wazuh (manager, indexador, dashboard y agentes) | 4.14.8 |
| Equipos monitoreados | 10 agentes Windows: CR-Salud (5), CR-Financiero (3), CR-Administrativo (1) y CR-Infraestructura (1) |

Para registrar las versiones exactas de las imágenes en tu ejecución:

```bash
docker image inspect --format '{{index .RepoDigests 0}}' wazuh/wazuh-manager:4.14.8
```

## 3. Despliegue

Los comandos `docker compose` se ejecutan desde `wazuh-docker/single-node`.

1. **Requisitos.** Docker Engine, el plugin Compose v2 (Ubuntu 24.04: `apt install docker-compose-v2`), `git`, `curl` y `vm.max_map_count >= 262144`.
2. **Instalar.**
   ```bash
   WAZUH_VERSION=4.14.8 ./scripts/deploy-wazuh.sh
   ```
   El script también publica los puertos 9200 y 55000 solo en localhost antes del primer arranque.
3. **Reemplazar las credenciales por defecto** y activar la contraseña de registro de agentes, según `docs/credential-rotation.md`.
4. **Crear los grupos.**
   ```bash
   for g in CR-Salud CR-Financiero CR-Administrativo CR-Infraestructura; do
     docker compose exec wazuh.manager /var/ossec/bin/agent_groups -a -g "$g" -q
   done
   ```
5. **Aplicar la configuración.**
   - Grupos: en el dashboard, *Management > Groups > (grupo) > Files > agent.conf*, pegar el contenido de `config/groups/<grupo>.agent.conf` adaptado a tus equipos y validar:
     ```bash
     docker compose exec wazuh.manager /var/ossec/bin/verify-agent-conf -f /var/ossec/etc/shared/CR-Salud/agent.conf
     ```
   - Reglas: en el dashboard, *Server management > Rules > Manage rules files*, añadir `config/rules/CR-RULE.xml` (después de reemplazar `APP_DIR_1` a `APP_DIR_4` en la regla 100006), validar y reiniciar:
     ```bash
     docker compose exec wazuh.manager /var/ossec/bin/wazuh-analysisd -t
     docker compose restart wazuh.manager
     ```
6. **Registrar un agente** (PowerShell como administrador). Si hay un agente anterior instalado, desinstalarlo primero. El nombre debe coincidir con el `agent_config name=` del grupo.
   ```powershell
   Invoke-WebRequest -Uri https://packages.wazuh.com/4.x/windows/wazuh-agent-<VERSION>-1.msi -OutFile $env:tmp\wazuh-agent
   msiexec.exe /i $env:tmp\wazuh-agent /q WAZUH_MANAGER='<IP_SERVIDOR>' WAZUH_AGENT_GROUP='<GRUPO>' WAZUH_AGENT_NAME='<NOMBRE_AGENTE>' WAZUH_REGISTRATION_PASSWORD='<CONTRASENA>'
   Start-Service wazuhsvc
   ```

## 4. Qué hacen las reglas

| Regla | Nivel | Qué detecta |
|---|---|---|
| 100008 | 0 | Ignora archivos temporales de Office (`~$*`) y `*.tmp` |
| 100005 | 5 | Archivo eliminado en una ruta vigilada (excluye temporales y `C:\Windows`) |
| 100009 | 12 | 20 o más eliminaciones (regla 100005) en 120 s en el mismo equipo; técnica MITRE ATT&CK T1485 |
| 100006 | 10 | Modificación dentro de directorios de aplicaciones críticas (T1565.001) |

## 5. Validacion con Test-FIM.ps1

En el equipo, sobre una carpeta que el agente vigile en tiempo real:

```powershell
.\Test-FIM.ps1 -Path 'C:\Users\USER\Documents\CRITICAL_FOLDER_1'
```

El script imprime una etiqueta (`fimtest-AAAAMMDD-HHMMSS`). En el servidor, con esa etiqueta:

```bash
curl -k -u admin "https://localhost:9200/wazuh-alerts-*/_search?pretty&filter_path=hits.hits._source.rule.id,hits.hits._source.rule.level,hits.hits._source.syscheck.path" \
  -H 'Content-Type: application/json' \
  -d '{"size":50,"sort":[{"@timestamp":"desc"}],"query":{"bool":{"filter":[{"wildcard":{"syscheck.path":"*fimtest-ETIQUETA*"}},{"range":{"@timestamp":{"gte":"now-30m"}}}]}}}'
```

Resultado esperado: el archivo normal genera las reglas 554 (creación), 550 (modificación) y 100005 (eliminación); el archivo temporal `~$` no genera alerta (regla 100008); la ráfaga de 25 archivos genera la regla 100009 (nivel 12), que se busca filtrando por `rule.id`.

## 6. Estado de validación y limitaciones

| Elemento | Estado |
|---|---|
| `Test-FIM.ps1` | Ejecutado en Windows PowerShell 5.1 sobre un equipo Windows el 5 de octubre de 2026: tres ejecuciones (dos con `-SkipBurst` y una con la ráfaga). Las alertas se leyeron del indexador y coinciden con las reglas esperadas. No se probó en PowerShell 7 ni en otras versiones de Windows |
| Reglas y `agent.conf` | Son los archivos desplegados en el servidor del estudio, con marcadores en lugar de datos reales. Probados solo con eventos sintéticos y en un equipo |
| `harden-ports.sh` | Probado contra un `docker-compose.yml` simulado, incluida la ruta de error. El mismo cambio se aplicó a mano en el servidor real; el script en sí no se ejecutó sobre él |
| `deploy-wazuh.sh` | Solo verificación de sintaxis (`bash -n`). **No se ejecutó** contra una instalación real ni de prueba |
| `docs/credential-rotation.md` | Procedimiento manual aplicado en el servidor de referencia (ver `CHANGELOG.md`) |
| `docs/operacion.md` | Procedimiento propuesto; no se sometió a simulacro |

Limitaciones del estudio que afectan a las reglas:

- Un solo sitio, 10 equipos y un periodo de observación corto.
- La agregación por equipo de la regla 100009 (`same_location`) no se verificó con dos equipos a la vez.
- No se midió la latencia de detección: los relojes del servidor y del equipo no estaban sincronizados.
- La regla 100009 solo cuenta eliminaciones; no detecta cifrado en el lugar. La regla 100008 ignora los archivos `.tmp`.
- Las descripciones de 100005 y 100006 incluyen la ruta del archivo (`$(file)`), por lo que las alertas contienen rutas.
- Alertas de evaluación de configuración (SCA): su volumen no se ajustó.

Ejecuta los scripts primero en un entorno de pruebas.

## 7. Seguridad y privacidad

- Una instalación nueva usa credenciales públicas por defecto. Reemplázalas antes de conectar agentes y activa la contraseña de registro de agentes.
- Los puertos publicados por Docker se saltan `ufw`; enlazar a `127.0.0.1` es el control fiable. Los agentes necesitan 1514/tcp y 1515/tcp, y el dashboard escucha en 443. El puerto 514/udp (syslog) queda publicado.
- El monitoreo de equipos en una institución de salud toca datos personales del personal y posiblemente de pacientes o donantes. FIM registra rutas, nombres de usuario y de equipo; `report_changes` no está activado, por lo que el contenido de los archivos no se copia a las alertas.
- Nunca subas `.env`, certificados, `client.keys`, respaldos ni alertas crudas. No publiques nombres de equipos, usuarios, rutas ni direcciones IP reales.
