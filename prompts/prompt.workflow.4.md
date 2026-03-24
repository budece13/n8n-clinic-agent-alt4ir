Eres un experto en n8n y debes construir un workflow de producción en formato JSON 
importable directamente en n8n (versión 1.x)(Impórtalo tú de manera autónoma en mi instancia de n8n con uso de mi api key disponible en .mcp.json). El workflow se llama 
"WA-Conversation-State" y actúa como sub-workflow de gestión centralizada del 
estado de sesión y contexto de conversación para el sistema de agente WhatsApp.

## FUNCIÓN DE ESTE WORKFLOW
Centraliza todas las operaciones de lectura/escritura de estado de sesión. 
Es llamado tanto por WA-Inbound-Orchestrator como por los schedulers de 
recordatorios. Actúa como la capa de abstracción de estado del sistema.

## TRIGGER
Nodo: Execute Workflow Trigger
Recibe:
{
  "action": "get_session" | "save_session" | "mark_reminder_responded" | 
             "get_pending_reminders_24h" | "get_pending_reminders_3h" | 
             "clear_session" | "get_appointment_context",
  "phone": "string (requerido para acciones de sesión)",
  "clinic_id": "string",
  "session_data": "object (solo para save_session)",
  "appointment_id": "UUID (solo para mark_reminder_responded)",
  "hours_ahead": "number (para get_pending_reminders)"
}

## NODOS Y LÓGICA POR ACCIÓN

### Switch Node principal → 6 ramas

---
### RAMA 1: get_session
Nodo Postgres:
SELECT 
  cs.session_data,
  cs.last_interaction,
  cs.appointment_context,
  cs.updated_at,
  a.id as active_appointment_id,
  a.service,
  a.datetime as appointment_datetime,
  a.status,
  a.reminder_24h_sent,
  a.reminder_responded
FROM conversation_sessions cs
LEFT JOIN appointments a ON (
  a.patient_phone = cs.phone 
  AND a.datetime > NOW() 
  AND a.status NOT IN ('cancelled')
)
WHERE cs.phone = $phone
ORDER BY a.datetime ASC
LIMIT 1;

Si no hay sesión: devuelve { session_data: {}, is_new_user: true }
Si hay sesión: devuelve datos completos + is_new_user: false

---
### RAMA 2: save_session
Nodo Code para preparar datos:
- Truncar session_data.message_history a los últimos 10 mensajes
- Añadir timestamp de actualización
- Serializar a JSONB

Nodo Postgres:
INSERT INTO conversation_sessions (phone, clinic_id, session_data, last_interaction, updated_at)
VALUES ($phone, $clinic_id, $session_data::jsonb, NOW(), NOW())
ON CONFLICT (phone) DO UPDATE SET
  session_data = EXCLUDED.session_data,
  last_interaction = NOW(),
  updated_at = NOW();

Devuelve: { success: true }

---
### RAMA 3: mark_reminder_responded
Nodo Postgres:
UPDATE appointments 
SET reminder_responded = true, updated_at = NOW()
WHERE id = $appointment_id;

Devuelve: { success: true, appointment_id }

---
### RAMA 4: get_pending_reminders_24h
Nodo Postgres:
SELECT 
  a.id,
  a.patient_phone,
  a.patient_name,
  a.service,
  a.datetime,
  a.clinic_id,
  c.name as clinic_name,
  c.timezone
FROM appointments a
JOIN clinics c ON a.clinic_id = c.clinic_id
WHERE 
  a.status = 'scheduled'
  AND a.reminder_24h_sent = false
  AND a.datetime BETWEEN NOW() + INTERVAL '23 hours' 
                     AND NOW() + INTERVAL '25 hours'
ORDER BY a.datetime ASC;

Devuelve: array de citas pendientes de recordatorio 24h

---
### RAMA 5: get_pending_reminders_3h
Nodo Postgres:
SELECT 
  a.id,
  a.patient_phone,
  a.patient_name,
  a.service,
  a.datetime,
  a.clinic_id,
  c.name as clinic_name,
  c.timezone
FROM appointments a
JOIN clinics c ON a.clinic_id = c.clinic_id
WHERE 
  a.status IN ('scheduled', 'confirmed')
  AND a.reminder_24h_sent = true
  AND a.reminder_responded = false
  AND a.reminder_3h_sent = false
  AND a.datetime BETWEEN NOW() + INTERVAL '2 hours 30 minutes' 
                     AND NOW() + INTERVAL '3 hours 30 minutes'
ORDER BY a.datetime ASC;

Devuelve: array de citas pendientes de recordatorio 3h

---
### RAMA 6: get_appointment_context
Permite al orquestador saber si hay una cita reciente en progreso de creación 
para este usuario (conversación multi-turno de agendamiento).

Nodo Postgres:
SELECT session_data->>'appointment_in_progress' as appointment_draft
FROM conversation_sessions
WHERE phone = $phone AND updated_at > NOW() - INTERVAL '30 minutes';

Devuelve el borrador de cita en progreso si existe.

## MANEJO DE ERRORES
- Si Postgres no responde: intentar 3 veces con backoff exponencial (1s, 3s, 9s)
- Loguear todos los errores en workflow_errors
- Devolver siempre un objeto estructurado, nunca propagar error raw

## NOTA DE DISEÑO
Este workflow puede parecer simple pero es crítico: centralizar aquí todas las 
queries de estado significa que si necesitas cambiar de Postgres a otro sistema 
(Redis, MongoDB, etc.) solo cambias este workflow, no los otros 5. Es el 
Data Access Layer del sistema.

## OUTPUT ESPERADO
JSON completo importable en n8n. El workflow debe ser liviano y rápido 
(sin llamadas LLM, solo operaciones de DB). Tiempo de respuesta objetivo: <200ms.