Eres un experto en n8n y debes construir un workflow de producción en formato JSON 
importable directamente en n8n (versión 1.x)(Impórtalo tú de manera autónoma en mi instancia de n8n con uso de mi api key disponible en .mcp.json). El workflow se llama 
"WA-Inbound-Orchestrator" y es el núcleo central de un agente de WhatsApp para 
gestión de citas en clínicas médicas.

## CONTEXTO DEL SISTEMA COMPLETO
Este sistema consta de 5 workflows interconectados:
1. WA-Inbound-Orchestrator (ESTE) — recibe mensajes WA, orquesta con AI Agent (gestión de sesión integrada)
2. WA-Appointments-Manager — sub-workflow para CRUD de citas
3. WA-Clinic-Info-RAG — sub-workflow para FAQ e info de servicios
4. WA-Reminder-24h-Scheduler — scheduler independiente de recordatorios 24h
5. WA-Reminder-3h-Followup-Scheduler — scheduler de recordatorios 3h

## FUNCIÓN DE ESTE WORKFLOW
Recibir TODOS los mensajes entrantes de WhatsApp Cloud API, interpretarlos mediante 
un AI Agent con LLM, y enrutar la acción al sub-workflow correspondiente. Después, 
enviar la respuesta generada de vuelta al usuario por WhatsApp.

## NODOS QUE DEBE CONTENER (en este orden lógico)

### 1. Webhook Node
- Método: POST
- Path: /webhook/whatsapp-inbound
- Responde inmediatamente con 200 OK (importante para WhatsApp Cloud API que exige 
  respuesta en <5s)
- Extrae del body: object.entry[0].changes[0].value.messages[0]
- Campos relevantes: from (phone), text.body (mensaje), id (message_id), timestamp, 
  type (text/audio/image)

### 2. Nodo "Normalize Message" (Code Node / Set Node)
Normaliza el payload a esta estructura estándar:
{
  "phone": "{{from}}",
  "message": "{{text.body}}",
  "message_id": "{{id}}",
  "timestamp": "{{timestamp}}",
  "message_type": "{{type}}",
  "clinic_id": "default" // se resolverá por número de teléfono de destino
}
Si el mensaje no es de tipo "text", responder con mensaje de "solo acepto texto por 
ahora" y terminar el flujo.

### 3. Nodo "Load Session" (Postgres Node)
Query:
SELECT session_data, last_interaction, appointment_context 
FROM conversation_sessions 
WHERE phone = $1 AND updated_at > NOW() - INTERVAL '24 hours'
LIMIT 1;

Si no existe sesión, devolver objeto vacío {}.

### 4. Nodo "Check Reminder Response" (Code Node)
Verifica si el mensaje es respuesta a un recordatorio pendiente:
- Query a tabla appointments: WHERE patient_phone = $phone 
  AND reminder_24h_sent = true AND reminder_responded = false 
  AND datetime > NOW()
- Si existe cita pendiente de respuesta, agregar flag is_reminder_response: true 
  al contexto, junto con appointment_id

### 5. AI Agent Node (LangChain AI Agent)
- Modelo: gpt-4o (configurable via credential)
- System Prompt:
  "Eres un asistente de IA para clínicas médicas que gestiona citas por WhatsApp. 
   Eres amable, profesional y conciso. Siempre respondes en el idioma del usuario.
   
   CLÍNICA: {{clinic_name}} 
   USUARIO: {{phone}}
   CONTEXTO DE SESIÓN: {{session_data}}
   FECHA Y HORA ACTUAL: {{$now}}
   
   Si el usuario está respondiendo a un recordatorio (is_reminder_response=true), 
   prioriza confirmar o cancelar esa cita antes de cualquier otra intención.
   
   Usa las herramientas disponibles para consultar disponibilidad, agendar, 
   cancelar citas o buscar información de la clínica. Nunca inventes disponibilidad.
   Siempre confirma los datos antes de crear una cita."

- Window Buffer Memory: 10 mensajes, usando Postgres como backend 
  (tabla: agent_memory, key: phone)

- Tools (Execute Workflow calls):
  a) tool_check_and_book_appointment
     → Llama a WA-Appointments-Manager
     → Input: { action: "create"|"check"|"cancel"|"reschedule", phone, 
                service, preferred_date, preferred_time, clinic_id }
     → Usar cuando usuario quiere agendar, consultar o modificar cita
  
  b) tool_get_clinic_information  
     → Llama a WA-Clinic-Info-RAG
     → Input: { question: string, clinic_id: string }
     → Usar cuando usuario pregunta por servicios, precios, horarios, FAQ
  
  c) tool_confirm_reminder_response
     → Llama a WA-Appointments-Manager con action: "confirm_from_reminder"
     → Input: { appointment_id, response: "confirm"|"cancel"|"reschedule", phone }
     → Usar SOLO cuando is_reminder_response=true

### 6. Nodo "Save Session" (Postgres Node)
INSERT INTO conversation_sessions (phone, session_data, last_interaction, updated_at)
VALUES ($1, $2, NOW(), NOW())
ON CONFLICT (phone) DO UPDATE SET 
  session_data = $2, 
  last_interaction = NOW(),
  updated_at = NOW();

session_data debe incluir: el último intent detectado, datos de cita en curso 
(si hay), y los últimos 3 mensajes del contexto.

### 7. Nodo "Send WhatsApp Response" (HTTP Request Node)
- URL: https://graph.facebook.com/v18.0/{{PHONE_NUMBER_ID}}/messages
- Method: POST
- Auth: Bearer token (WhatsApp Cloud API token desde credentials)
- Body:
{
  "messaging_product": "whatsapp",
  "to": "{{phone}}",
  "type": "text",
  "text": { "body": "{{ai_agent_response}}" }
}

### 8. Error Handler (nodo Error Trigger + Postgres insert)
Captura cualquier error del flujo y:
- Guarda en tabla workflow_errors: { workflow, error_message, phone, timestamp }
- Envía mensaje genérico al usuario: "Disculpa, tuve un problema técnico. 
  Por favor intenta de nuevo en unos minutos."
- Notifica por email/Slack al equipo técnico

## ESQUEMA DE BASE DE DATOS REQUERIDO
Incluye al final del JSON los siguientes CREATE TABLE como comentario de documentación:

CREATE TABLE conversation_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone VARCHAR(20) UNIQUE NOT NULL,
  session_data JSONB DEFAULT '{}',
  last_interaction TIMESTAMP,
  appointment_context JSONB DEFAULT '{}',
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE agent_memory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id VARCHAR(100),
  messages JSONB DEFAULT '[]',
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE workflow_errors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow VARCHAR(100),
  error_message TEXT,
  phone VARCHAR(20),
  payload JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

## REQUISITOS DE PRODUCCIÓN
- Todos los credentials deben referenciarse por nombre, no hardcodeados
- Incluir nodos de logging (Postgres) en puntos críticos
- El webhook debe validar el token de verificación de WhatsApp (parámetro 
  hub.verify_token) para el proceso de setup inicial
- Manejo explícito de mensajes de tipo no-text (audio, imagen, documento): 
  responder con texto indicando que solo se acepta texto
- Timeout máximo del AI Agent: 25 segundos

## OUTPUT ESPERADO
Genera el workflow completo en formato JSON válido de n8n que pueda importarse 
directamente via Settings > Import Workflow en la UI de n8n. Incluye todos los 
nodos, sus parámetros completos, y las connections entre ellos en el formato 
estándar de n8n {"nodes": [...], "connections": {...}}.