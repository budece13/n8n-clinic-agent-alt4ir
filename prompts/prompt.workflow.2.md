Eres un experto en n8n y debes construir un workflow de producción en formato JSON 
importable directamente en n8n (versión 1.x)(Impórtalo tú de manera autónoma en mi instancia de n8n con uso de mi api key disponible en .mcp.json). El workflow se llama 
"WA-Appointments-Manager" y actúa como sub-workflow especializado en toda la lógica 
de gestión de citas del sistema de agente WhatsApp para clínicas.

## FUNCIÓN DE ESTE WORKFLOW
Es llamado exclusivamente como sub-workflow desde WA-Inbound-Orchestrator mediante 
el nodo Execute Workflow. Gestiona creación, consulta, modificación y cancelación de 
citas, sincronizando simultáneamente con: (a) la API propietaria de la clínica, 
(b) Calendly o Google Calendar, y (c) la base de datos propia del sistema.

## TRIGGER
Nodo: Execute Workflow Trigger (no Webhook)
Recibe el siguiente objeto de entrada:
{
  "action": "check_availability" | "create" | "cancel" | "reschedule" | 
             "confirm_from_reminder" | "list_upcoming",
  "phone": "string",
  "clinic_id": "string",
  "service": "string (opcional según acción)",
  "preferred_date": "YYYY-MM-DD (opcional)",
  "preferred_time": "HH:MM (opcional)",
  "appointment_id": "UUID (requerido para cancel/reschedule/confirm_from_reminder)",
  "response": "confirm|cancel|reschedule (solo para confirm_from_reminder)"
}

## NODOS Y LÓGICA POR ACCIÓN

### Nodo 1: "Router por Acción" (Switch Node)
Enruta según el campo `action` a las siguientes ramas:

---
### RAMA A: check_availability
1. Nodo "Get Clinic Config" (Postgres):
   SELECT api_type, api_url, api_key, calendly_link, google_calendar_id, timezone
   FROM clinics WHERE clinic_id = $1;

2. Nodo "Check Availability - Clinic API" (HTTP Request):
   - URL dinámica según api_url de la clínica
   - Headers: Authorization con api_key
   - Body: { service, date: preferred_date, timezone }
   - Manejo de error: si falla, continuar con calendario alternativo

3. Nodo "Check Availability - Calendly" (HTTP Request, si aplica):
   - GET https://api.calendly.com/event_type_available_times
   - Headers: Authorization Bearer {{calendly_token}}
   - Params: { event_type_uuid, start_time, end_time }

4. Nodo "Merge & Format Slots" (Code Node):
   Combina disponibilidad de ambas fuentes, elimina duplicados, 
   devuelve máximo 5 slots en formato:
   [{ datetime: "YYYY-MM-DD HH:MM", source: "clinic_api"|"calendly" }]

---
### RAMA B: create
1. Nodo "Get Clinic Config" (Postgres): igual que rama A
2. Nodo "Validate Input" (Code Node): 
   - Verifica que phone, service, preferred_date, preferred_time no sean nulos
   - Valida formato de fecha y hora
   - Lanza error descriptivo si falta algún campo
3. Nodo "Create in Clinic API" (HTTP Request):
   - POST a api_url/appointments
   - Body: { patient_phone: phone, service, datetime, notes }
   - Guarda external_id de la respuesta
4. Nodo "Create in Calendly/Google Calendar" (HTTP Request):
   - Si calendly: POST https://api.calendly.com/scheduled_events
   - Si google_calendar: POST https://www.googleapis.com/calendar/v3/calendars/{id}/events
   - Body estándar con summary, start, end, description (incluye phone)
5. Nodo "Save to DB" (Postgres):
   INSERT INTO appointments (
     clinic_id, patient_phone, service, datetime, 
     external_id, external_calendar_id, status, created_at
   ) VALUES (...) RETURNING id, datetime, service;
6. Nodo "Format Success Response" (Set Node):
   { 
     success: true, 
     message: "Cita creada el {fecha} a las {hora} para {service}",
     appointment_id: uuid,
     datetime: ISO string,
     confirmation_code: external_id
   }

---
### RAMA C: cancel
1. Nodo "Get Appointment" (Postgres):
   SELECT * FROM appointments WHERE id = $appointment_id AND patient_phone = $phone;
   Si no existe: devolver error "Cita no encontrada"
2. Nodo "Cancel in Clinic API" (HTTP Request):
   DELETE/PATCH a api_url/appointments/{external_id} con status: "cancelled"
3. Nodo "Cancel in Calendar" (HTTP Request):
   - Calendly: POST a cancellation endpoint
   - Google: DELETE event
4. Nodo "Update DB" (Postgres):
   UPDATE appointments SET status = 'cancelled', updated_at = NOW()
   WHERE id = $appointment_id;
5. Devuelve: { success: true, message: "Cita cancelada correctamente" }

---
### RAMA D: reschedule
1. Obtener cita actual (como en cancel)
2. Cancelar en sistemas externos (como en cancel)
3. Crear nueva cita con nuevas fecha/hora (como en create)
4. Actualizar DB con status 'rescheduled' en la antigua, nueva entrada para la nueva
5. Devuelve: { success: true, message: "Cita reprogramada para {nueva_fecha}" }

---
### RAMA E: confirm_from_reminder
1. Nodo "Get Appointment" (Postgres): SELECT * WHERE id = $appointment_id
2. Switch por `response`:
   - "confirm": UPDATE appointments SET status='confirmed', 
     reminder_responded=true WHERE id=$appointment_id
     → Devuelve: "¡Perfecto! Tu cita está confirmada. Te esperamos."
   - "cancel": ejecutar rama C
   - "reschedule": devolver "¿Para qué fecha y hora te viene mejor?"
     (el orquestador continuará el flujo de reagendamiento)
3. Update reminder_responded = true en cualquier caso

---
### RAMA F: list_upcoming
1. Postgres: SELECT service, datetime, status FROM appointments 
   WHERE patient_phone = $phone AND datetime > NOW() AND status != 'cancelled'
   ORDER BY datetime ASC LIMIT 3;
2. Formatea lista legible en texto natural

## MANEJO DE ERRORES (global para todas las ramas)
- Nodo Error Trigger conectado a todas las ramas
- Si la API de la clínica falla: intentar 2 retries con delay de 3s, 
  si sigue fallando usar Calendly como fallback
- Si Calendly/Google Calendar falla: registrar error pero continuar si la API 
  de clínica fue exitosa
- Siempre guardar en tabla workflow_errors los fallos con contexto completo
- Devolver al orquestador un objeto con { success: false, error: "mensaje_amigable" }
  nunca propagar el error técnico al usuario final

## ESQUEMA DE BASE DE DATOS REQUERIDO (incluir como comentario)
CREATE TABLE appointments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id VARCHAR(100) NOT NULL,
  patient_phone VARCHAR(20) NOT NULL,
  patient_name VARCHAR(200),
  service VARCHAR(200),
  datetime TIMESTAMP NOT NULL,
  external_id VARCHAR(200),
  external_calendar_id VARCHAR(200),
  status VARCHAR(50) DEFAULT 'scheduled',
  reminder_24h_sent BOOLEAN DEFAULT false,
  reminder_24h_sent_at TIMESTAMP,
  reminder_responded BOOLEAN DEFAULT false,
  reminder_3h_sent BOOLEAN DEFAULT false,
  reminder_3h_sent_at TIMESTAMP,
  notes TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE clinics (
  clinic_id VARCHAR(100) PRIMARY KEY,
  name VARCHAR(200),
  api_type VARCHAR(50), -- 'rest_api' | 'calendly' | 'google_calendar'
  api_url VARCHAR(500),
  api_key VARCHAR(500),
  calendly_token VARCHAR(500),
  calendly_event_type_uuid VARCHAR(200),
  google_calendar_id VARCHAR(200),
  timezone VARCHAR(100) DEFAULT 'Europe/Madrid',
  whatsapp_phone_number_id VARCHAR(100),
  created_at TIMESTAMP DEFAULT NOW()
);

## OUTPUT ESPERADO
JSON completo importable en n8n con todos los nodos, sus configuraciones completas, 
manejo de credenciales por nombre (nunca hardcodeadas), y el mapa de connections.
El workflow debe poder ejecutarse de forma aislada para testing pasándole 
manualmente el payload de entrada por el nodo trigger.