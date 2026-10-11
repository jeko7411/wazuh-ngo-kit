# Procedimiento operativo mínimo

Procedimiento para quien opere el servidor de monitoreo, incluido el suplente del responsable de TI.
Todos los comandos se ejecutan desde `wazuh-docker/single-node`. Es un procedimiento propuesto: los comandos son los usados en el estudio, pero el procedimiento como tal no se sometió a simulacro.

## 1. Tras un corte de energía

1. Encender el servidor. Para que se encienda solo cuando vuelve la energía, activar en la BIOS la opción de recuperación tras pérdida de corriente alterna (según el fabricante: "Restore on AC Power Loss" o "AC Power Recovery", en "Power On").
2. Comprobar que Docker arrancó y que los tres contenedores están en ejecución:
   ```bash
   sudo docker compose ps
   ```
   Si alguno no está en ejecución: `sudo docker compose up -d`.
3. Comprobar que el indexador responde (pide la contraseña de `admin`):
   ```bash
   curl -sk -u admin "https://localhost:9200/_cluster/health?pretty" | grep status
   ```
   Se espera `green` o `yellow`.

## 2. Comprobar que el monitoreo recibe datos

```bash
sudo docker compose exec -T wazuh.manager /var/ossec/bin/agent_control -l
```
Los equipos encendidos deben aparecer como `Active`. Un equipo apagado aparece como `Disconnected`; es normal fuera de horario laboral.

Para confirmar que se están indexando alertas, abrir el dashboard (Threat Hunting / Events) y revisar que haya alertas recientes. Si el monitoreo deja de recibir datos y nadie se entera, el servicio queda ciego sin aviso: se recomienda una alerta externa cuando no lleguen datos.

## 3. Revisión de alertas

- Revisar a diario las alertas de nivel 12 o superior (por ejemplo, la regla 100009, borrado masivo).
- Las alertas de nivel 7 a 11 son, en su mayoría, hallazgos de configuración (SCA); revisarlas de forma periódica y no tratarlas como incidentes.

## 4. Alta de un equipo (agente)

1. Si el equipo tiene un agente anterior, desinstalarlo antes de borrar su entrada en el servidor.
2. Crear el grupo si no existe: `sudo docker compose exec wazuh.manager /var/ossec/bin/agent_groups -a -g NOMBRE_GRUPO -q`.
3. Instalar el agente con la línea `msiexec` del README, añadiendo `WAZUH_REGISTRATION_PASSWORD='...'`. El nombre del agente debe coincidir exactamente con el `agent_config name=` del grupo.

## 5. Contraseñas

Procedimiento en [credential-rotation.md](credential-rotation.md). No guardar contraseñas en el repositorio ni en el historial de la terminal.
