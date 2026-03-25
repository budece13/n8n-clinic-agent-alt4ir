# N8N-CLINIC-AGENT

## Propósito del Proyecto

Este entorno está diseñado para **crear workflows de n8n de alta calidad** orientados a la automatización y mejora de los sistemas de clínicas privadas del sector salud en España. El rol principal es traducir descripciones en lenguaje natural en workflows n8n listos para producción.

---

## Herramientas Disponibles

### 1. n8n-MCP (Servidor MCP)

Servidor MCP que conecta Claude con n8n. Proporciona acceso a:
- **1.084 nodos** (537 core + 547 community + 301 verificados)
- **2.709 plantillas de workflows** con metadatos completos
- **Gestión completa de workflows** en la instancia n8n (crear, leer, actualizar, eliminar, ejecutar)

**Repositorio:** https://github.com/czlonkowski/n8n-mcp

#### Instalación (Claude Code)

```bash
claude mcp add n8n-mcp \
  -e MCP_MODE=stdio \
  -e LOG_LEVEL=error \
  -e DISABLE_CONSOLE_OUTPUT=true \
  -- npx n8n-mcp
```

#### Variables de Entorno Requeridas

| Variable | Descripción | Obligatoria |
|---|---|---|
| `MCP_MODE` | Debe ser `stdio` para Claude Code | Sí |
| `LOG_LEVEL` | `error` en producción | Sí |
| `DISABLE_CONSOLE_OUTPUT` | `true` para evitar errores de parsing JSON | Sí |
| `N8N_API_URL` | URL de la instancia n8n (ej. `http://localhost:5678`) | Para gestión |
| `N8N_API_KEY` | API Key de la instancia n8n | Para gestión |

#### Herramientas MCP Disponibles (20 total)

**Documentación y búsqueda (sin credenciales):**
- `search_nodes` — Búsqueda de nodos por nombre, función o fuente
- `get_node` — Obtener documentación, propiedades y versiones de un nodo
- `validate_node` — Validar configuración de un nodo (modo minimal o full)
- `search_templates` — Buscar plantillas por palabra clave, nodos usados o tipo de tarea
- `get_template` — Obtener JSON completo de una plantilla
- `validate_workflow` — Validar estructura completa de un workflow
- `tools_documentation` — Guía de uso de las herramientas MCP

**Gestión de workflows (requiere `N8N_API_URL` y `N8N_API_KEY`):**
- `n8n_create_workflow` — Crear y desplegar un nuevo workflow
- `n8n_get_workflow` — Obtener workflow por ID
- `n8n_update_full_workflow` — Reemplazar workflow completo
- `n8n_update_partial_workflow` — Actualización parcial con diff (soporta operaciones batch)
- `n8n_delete_workflow` — Eliminar workflow permanentemente
- `n8n_list_workflows` — Listar workflows con filtros y paginación

**Ejecución y sistema (requiere credenciales):**
- `n8n_test_workflow` — Ejecutar workflow con detección automática del trigger
- `n8n_executions` — Gestión de ejecuciones (listar, obtener, eliminar)
- `n8n_validate_workflow` — Validar workflow por ID en la instancia
- `n8n_autofix_workflow` — Reparar errores comunes automáticamente
- `n8n_workflow_versions` — Historial de versiones
- `n8n_deploy_template` — Desplegar plantillas de n8n.io directamente
- `n8n_health_check` — Verificar conectividad con la API

---

### 2. n8n-Skills (Skills de Claude Code)

7 skills complementarias que enseñan a Claude cómo construir workflows n8n de producción usando n8n-mcp. Se activan automáticamente según el contexto de la consulta.

**Repositorio:** https://github.com/czlonkowski/n8n-skills

#### Instalación

```bash
/plugin install czlonkowski/n8n-skills
```

O manualmente:
```bash
git clone https://github.com/czlonkowski/n8n-skills.git
cp -r n8n-skills/skills/* ~/.claude/skills/
```

#### Skills Incluidas

| Skill | Propósito |
|---|---|
| **n8n Expression Syntax** | Patrones `{{}}`, variables `$json`, `$node`, `$now`, `$env` |
| **n8n MCP Tools Expert** | Uso efectivo de las herramientas MCP (máxima prioridad) |
| **n8n Workflow Patterns** | 5 patrones arquitecturales probados en producción |
| **n8n Validation Expert** | Interpretación de errores, falsos positivos, auto-sanitización |
| **n8n Node Configuration** | Configuración de 525+ nodos, dependencias entre propiedades |
| **n8n Code JavaScript** | Patrones de Code node JS, formato de retorno correcto |
| **n8n Code Python** | Limitaciones de Python en n8n, cuándo NO usarlo |

---

## Subagente Disponible

### `n8n-expert`

Subagente especializado en construir, depurar y optimizar workflows n8n para entornos clínicos. Ubicado en `.claude/agents/n8n-expert.md`.

**Cuándo usarlo:** para cualquier tarea de creación, análisis, depuración u optimización de workflows n8n.

---

## Estructura del Proyecto

```
n8n-clinic-agent/
├── CLAUDE.md              # Este archivo
├── .claude/
│   ├── agents/
│   │   └── n8n-expert.md  # Subagente especializado
│   └── settings.local.json
├── prompts/               # Plantillas de prompts reutilizables
├── schemas/               # Esquemas JSON para validación
├── templates/             # Plantillas de workflows base
├── examples/              # Workflows de ejemplo
├── outputs/               # Workflows generados y exportados
└── tests/                 # Tests de validación de workflows

```

---

## Flujo de Trabajo Principal

### Proceso para Crear un Workflow

1. **Recibir** descripción en lenguaje natural del workflow requerido
2. **Buscar** nodos relevantes con `search_nodes` y plantillas con `search_templates`
3. **Consultar** documentación de nodos con `get_node`
4. **Construir** el workflow JSON siguiendo los patrones de las skills
5. **Validar** el workflow con `validate_workflow` antes de desplegar
6. **Desplegar** con `n8n_create_workflow` a la instancia n8n
7. **Probar** con `n8n_test_workflow` y verificar la ejecución
8. **Guardar** crear una copia del JSON del workflow output final en la carpeta outputs/

### Patrones de Workflow para Clínicas (5 Arquitecturas Base)

| Patrón | Casos de Uso Clínicos |
|---|---|
| **Webhook Processing** | Recepción de citas, formularios de pacientes, alertas |
| **HTTP API** | Integración con HIS/EMR, laboratorios, facturación |
| **Database Operations** | Registro de pacientes, historial clínico, inventario |
| **AI Workflows** | Asistentes virtuales, clasificación de síntomas, resúmenes |
| **Scheduled Workflows** | Recordatorios de citas, informes, auditorías de cumplimiento |

---

## Reglas Críticas de Producción

### Seguridad (Contexto Sanitario Español)

- **Nunca** exponer datos de pacientes (nombre, DNI, diagnóstico, medicación) en logs o respuestas de webhook sin cifrado
- Usar siempre **credenciales de n8n** para almacenar API keys, nunca hardcodearlas en el workflow
- Los workflows que manejen datos de salud deben cumplir con el **RGPD** y la **Ley Orgánica 3/2018 (LOPDGDD)**
- Implementar autenticación en todos los webhooks que reciban datos de pacientes (header auth o basic auth mínimo)

### Calidad y Fiabilidad

- **Nunca** modificar directamente workflows en producción — siempre copiar, modificar en desarrollo, validar y desplegar
- Añadir siempre nodos de **manejo de errores** (Error Trigger, try/catch en Code nodes)
- Nomenclatura de nodos: descriptiva y en español (ej. "Obtener Cita", "Enviar Confirmación SMS")
- Validar el workflow con `validate_workflow` antes de cada despliegue
- Los datos de webhook están en `$json.body`, no en `$json` directamente

### Gotchas Frecuentes de n8n

- El tipo de nodo usa formato `nodes-base.*` (no `n8n-nodes-base.*`) en las búsquedas MCP
- Los nodos IF enrutan a ramas `TRUE`/`FALSE` usando el parámetro `branch` en operaciones de conexión
- Los datos de webhook están bajo `$json.body`
- El formato de retorno correcto en Code nodes JavaScript es `[{json: {...}}]`
- No confiar en valores por defecto de parámetros — siempre configurar explícitamente los campos requeridos
- Python en Code nodes **no tiene acceso** a librerías externas (requests, pandas, numpy) — usar JavaScript para el 95% de los casos

---

## Contexto del Dominio: Clínicas Privadas en España

### Sistemas Típicos a Integrar

- **HIS/Software de gestión clínica:** Doctoralia, Gesden, Clinic Cloud, iClinic, Medigest
- **Comunicación:** WhatsApp Business API, SMS (Twilio, Vonage), email (Gmail, Outlook, SendGrid)
- **Pagos:** Stripe, Redsys (pasarela bancaria española)
- **Laboratorios:** APIs de laboratorios de referencia (Synlab, Eurofins, Análisis Clínicos)
- **Facturación:** FacturaDirecta, Holded, Sage, integración con mutuas (Adeslas, Mapfre Salud, Sanitas)
- **Almacenamiento:** Google Drive, SharePoint para documentos clínicos
- **Firma digital:** Signaturit, DocuSign para consentimientos informados

### Flujos de Automatización Prioritarios

1. **Gestión de citas:** confirmación, recordatorio (24h/1h antes), lista de espera
2. **Onboarding de paciente:** recogida de datos, consentimientos, historia clínica inicial
3. **Resultados de laboratorio:** recepción, clasificación por urgencia, notificación al médico y paciente
4. **Facturación y cobro:** generación de facturas, envío, seguimiento de impagos
5. **Informes de cumplimiento:** auditorías RGPD, registros de acceso a datos de salud
6. **Comunicación interna:** notificaciones al equipo, cambios de turno, alertas de stock de material

---

## Comandos de Verificación Rápida

```bash
# Verificar que n8n-mcp está activo
claude mcp list

# Ver estado de la instancia n8n (cuando esté configurada)
# Usar herramienta: n8n_health_check
```
