# N8N Clinic Agent — Alt4ir

> Agente de automatización para clínicas privadas construido sobre n8n. Convierte descripciones en lenguaje natural en workflows de producción listos para desplegar.

---

## Arquitectura del Agente WhatsApp

```
WhatsApp ──► WA-Inbound-Orchestrator
                      │
          ┌───────────┼────────────────┐
          ▼           ▼                ▼
  WA-Appointments  WA-Clinic-     WA-Conversation
     -Manager       Info-RAG          -State

  WA-Reminder-24h-Scheduler  ──► recordatorio 24h antes
  WA-Reminder-3h-Followup    ──► seguimiento 3h antes
```

| Workflow | Rol |
|---|---|
| `WA-Inbound-Orchestrator` | Núcleo central — recibe mensajes y enruta al sub-workflow correcto |
| `WA-Appointments-Manager` | Lógica completa de citas (crear, modificar, cancelar) |
| `WA-Clinic-Info-RAG` | Responde preguntas sobre la clínica con RAG + LangChain |
| `WA-Conversation-State` | Gestión centralizada del estado de conversación por paciente |
| `WA-Reminder-24h-Scheduler` | Recordatorios automáticos 24h antes de cada cita |
| `WA-Reminder-3h-Followup` | Seguimiento y confirmación 3h antes de la cita |

---

## Estructura

```
├── outputs/    # Workflows generados (JSON importable en n8n)
├── prompts/    # Prompts para generar cada workflow con Claude
├── .mcp.json   # Configuración n8n-mcp (URL + API Key)
└── CLAUDE.md   # Instrucciones del agente y reglas de producción
```

---

## Stack

- **n8n** — Motor de automatización (instancia en `n8n.alt4ir.com`)
- **n8n-mcp** — Servidor MCP que conecta Claude con n8n (1.084 nodos, 2.709 plantillas)
- **Claude Code** — Agente que genera, valida y despliega los workflows
- **WhatsApp Business API** — Canal de entrada de mensajes

---

## Uso

1. Describe el workflow en lenguaje natural o usa un prompt de `prompts/`
2. Claude genera el JSON, lo valida con `validate_workflow` y lo despliega en n8n
3. El workflow exportado se guarda en `outputs/`

---

## Cumplimiento

Los workflows que manejan datos de pacientes están diseñados conforme al **RGPD** y la **LOPDGDD** (Ley Orgánica 3/2018). Nunca se exponen datos clínicos en logs ni webhooks sin autenticación.
