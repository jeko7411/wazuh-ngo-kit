# Registro de validación

Qué se hizo en el servidor de referencia, cómo se verificó y qué queda pendiente. Los nombres, rutas y direcciones propios de la institución se reemplazan por marcadores.

Etiquetas de estado
- **Verificado**: se revisó la salida de los comandos durante el trabajo.
- **Reportado**: el operador indicó que se hizo, pero no se guardó la salida.
- **Pendiente**: aún no se hizo.

## 1. Entorno de referencia

| Elemento | Valor |
|---|---|
| Servidor | Ubuntu Server 24.04.4 LTS |
| Docker | Engine 29.1.3, Compose v2 2.40.3 |
| Wazuh | 4.14.8 (manager, indexador y dashboard en Docker, un solo nodo) |
| Equipos | 10 agentes Windows en 4 grupos: CR-Salud (5), CR-Financiero (3), CR-Administrativo (1) y CR-Infraestructura (1) |

## 2. Cambios y verificación

### Reglas personalizadas (Verificado con eventos sintéticos)
- Las reglas 100005, 100006, 100008 y 100009 de `config/rules/CR-RULE.xml` son las desplegadas en el servidor.
- Prueba sintética del 5 de octubre de 2026 en un equipo Windows: tres ejecuciones de `Test-FIM.ps1`, la tercera con una ráfaga de 25 archivos. Cada archivo normal generó las reglas 554, 550 y 100005; el archivo temporal `~$` de Office no generó alerta (regla 100008). En la ráfaga, la regla 100009 (nivel 12) se disparó una vez, al acumularse 20 eliminaciones en 120 segundos (la ventana incluía eliminaciones de las ejecuciones anteriores, por lo que se disparó con el archivo 18 de la ráfaga); las eliminaciones siguientes quedaron suprimidas por `ignore=300`.
- **No verificado:** que la regla 100009 agregue por equipo (`same_location`) con dos equipos a la vez; y la latencia de detección, porque entre el reloj del equipo y el del servidor había un desfase de aproximadamente un segundo, por lo que no se reporta ninguna latencia.

### Configuración por grupos (Verificado la sintaxis)
- Carpetas de documentos de trabajo en tiempo real; carpetas de aplicaciones limitadas a ejecutables y configuración; directorio de datos de base de datos ignorado; `report_changes` desactivado.
- El nombre del agente debe coincidir exactamente con el `agent_config name=` del grupo.

### Exposición de red (Verificado)
- Indexador (9200) y API (55000) publicados solo en `127.0.0.1` (`docker compose ps` muestra `127.0.0.1:9200` y `127.0.0.1:55000`). Los puertos 1514 y 1515 (agentes), 514/udp (syslog) y 443 (dashboard) no cambian.

### Credenciales (cambios entre el 4 y el 10 de octubre de 2026)
- Usuario del indexador `admin`: reemplazada (Verificado: el indexador responde con la clave nueva y la prueba de salida de Filebeat termina en OK).
- Usuario de la API `wazuh-wui`: reemplazada y sincronizada con el dashboard (Reportado: el operador confirmó la conexión; no se guardó la salida).
- Usuario del indexador `kibanaserver`: reemplazada el 10 de octubre de 2026 (Verificado desde la línea de comandos: la clave nueva autentica y la de fábrica devuelve HTTP 401).
- Contraseña de registro de agentes: activada y verificada el 10 de octubre de 2026 (Verificado, salida guardada): una solicitud sin contraseña fue rechazada y una con contraseña fue aceptada; antes del cambio, una solicitud sin contraseña registraba un agente.
- Usuario de la API `wazuh`: reemplazada (Verificado el 2026-10-11, 13:55 UTC).
- Comprobación conjunta de credenciales de fábrica (Verificado el 2026-10-11, 13:55 UTC, solo códigos HTTP): `wazuh:wazuh` devuelve 401; `wazuh-wui` con sus dos contraseñas de fábrica devuelve 401; `admin` y `kibanaserver` con su contraseña de fábrica devuelven 401; la contraseña nueva del usuario `wazuh` devuelve 200.

## 3. Pendiente

- Confirmar que la regla 100009 agrega por equipo, con una prueba simultánea en dos equipos.
- Medir la latencia de detección con los dos relojes sincronizados a la misma fuente NTP.
- Ejecutar `deploy-wazuh.sh` en un entorno de pruebas.
- Notificaciones para alertas de nivel 12 o superior, y retención de índices.
- Ajustar el volumen de alertas SCA.
