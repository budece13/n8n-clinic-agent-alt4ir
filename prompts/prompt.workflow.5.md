Eres un experto en n8n y debes construir un workflow de producción en formato JSON 
importable directamente en n8n (versión 1.x)(Impórtalo tú de manera autónoma en mi instancia de n8n con uso de mi api key disponible en .mcp.json). El workflow se llama 
"WA-Reminder-24h-Scheduler" y es un proceso autónomo que se ejecuta de forma 
programada para enviar recordatorios de citas a pacientes 24 horas antes de 
su cita mediante WhatsApp.

## FUNCIÓN DE ESTE WORKFLOW
Opera de forma completamente independiente del orquestador. Detecta citas que 
ocurrirán en aproximadamente 24 horas y que aún no tienen recordatorio enviado, 
envía el mensaje de recordatorio por WhatsApp Cloud API, y registra el envío en 
la base de datos. Este workflow NO espera respuesta del paciente — eso lo gestiona 
el orquestador cuando llegue el mensaje de respuesta.

## TRIGGER
Nodo: Schedule Trigger
- Intervalo: cada 30 minutos
- Timezone: Europe/Madrid (ajustar según deployment)
- Activo las 24h del día (los recordatorios pueden ser para mañana temprano)

## NODOS Y LÓGICA COMPLETA

### Nodo 1: "Fetch Appointments for 24h Reminder" (Postgres Node)
Query:
SELECT 
  a.id as appointment_id,
  a.patient_phone,
  a.patient_name,
  a.service,
  a.datetime,
  a.clinic_id,
  a.external_id,
  c.name as clinic_name,
  c.timezone,
  c.whatsapp_phone_number_id,
  c.whatsapp_token
FROM appointments a
JOIN clinics c ON a.clinic_id = c.clinic_id
WHERE 
  a.status IN ('scheduled', 'confirmed')
  AND a.reminder_24h_sent = false
  AND a.datetime >= NOW() + INTERVAL '23 hours'
  AND a.datetime <= NOW() + INTERVAL '25 hours'
ORDER BY a.datetime ASC
LIMIT 100;

### Nodo 2: "Check if Any Appointments Found" (IF Node)
Condición: {{ $json.length > 0 }}
- Si NO hay citas: → nodo "Log Empty Run" y terminar
- Si SÍ hay citas: → continuar al nodo 3

### Nodo 3: "Log Scheduler Run Start" (Postgres Node)
INSERT INTO scheduler_runs (workflow_name, appointments_found, started_at)
VALUES ('WA-Reminder-24h', {{ appointmentsCount }}, NOW())
RETURNING id;

### Nodo 4: "Split Into Items" (Split in Batches / Item Lists Node)
Procesa cada cita individualmente en un loop.
Batch size: 1 (para control preciso de rate limiting)

### Nodo 5: "Format WhatsApp Message" (Code Node)
Para cada cita, construye el mensaje personalizado:

const appt = items[0].json;
const fecha = new Date(appt.datetime).toLocaleDateString('es-ES', { 
  weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
  timeZone: appt.timezone 
});
const hora = new Date(appt.datetime).toLocaleTimeString('es-ES', { 
  hour: '2-digit', minute: '2-digit', timeZone: appt.timezone 
});
const nombre = appt.patient_name ? `Hola ${appt.patient_name}` : 'Hola';

const message = `${nombre} 👋

Te recordamos que tienes una cita en *${appt.clinic_name}* mañana:

📅 ${fecha}
🕐 ${hora}
💊 Servicio: ${appt.service}

¿Confirmas tu asistencia?
✅ Responde *SÍ* para confirmar
❌ Responde *NO* para cancelar
🔄 Responde *CAMBIAR* si necesitas otra fecha

Si tienes alguna duda, escríbenos aquí mismo.`;

return [{ json: { ...appt, message_text: message } }];

### Nodo 6: "Send WhatsApp Reminder" (HTTP Request Node)
- URL: https://graph.facebook.com/v18.0/{{ $json.whatsapp_phone_number_id }}/messages
- Method: POST
- Headers: 
  Content-Type: application/json
  Authorization: Bearer {{ $json.whatsapp_token }}
- Body:
{
  "messaging_product": "whatsapp",
  "to": "{{ $json.patient_phone }}",
  "type": "text",
  "text": { "body": "{{ $json.message_text }}" }
}
- Continuar en caso de error (para no bloquear el resto de recordatorios)
- Timeout: 10 segundos

### Nodo 7: "Check Send Success" (IF Node)
Condición: response status code === 200 o 201
- Si éxito: → Nodo 8 "Mark Sent in DB"
- Si fallo: → Nodo "Log Send Error"

### Nodo 8: "Mark Reminder Sent in DB" (Postgres Node)
UPDATE appointments 
SET 
  reminder_24h_sent = true,
  reminder_24h_sent_at = NOW(),
  updated_at = NOW()
WHERE id = $appointment_id;

### Nodo "Log Send Error" (Postgres Node, rama de error)
INSERT INTO reminder_errors (
  appointment_id, patient_phone, reminder_type, 
  error_response, created_at
) VALUES ($appointment_id, $phone, '24h', $error_body::jsonb, NOW());

### Nodo 9: "Rate Limit Delay" (Wait Node)
- Espera: 500ms entre cada mensaje
- Previene superar límites de WhatsApp Cloud API

### Nodo 10: "Log Scheduler Run Complete" (Postgres Node)
UPDATE scheduler_runs 
SET 
  appointments_processed = {{ processedCount }},
  appointments_succeeded = {{ succeededCount }},
  appointments_failed = {{ failedCount }},
  completed_at = NOW()
WHERE id = {{ schedulerRunId }};

### Nodo "Log Empty Run" (Postgres Node, rama vacía)
INSERT INTO scheduler_runs (
  workflow_name, appointments_found, appointments_processed, 
  started_at, completed_at
) VALUES ('WA-Reminder-24h', 0, 0, NOW(), NOW());

## MANEJO DE ERRORES CRÍTICOS
- Error de conexión a Postgres: notificar por email al equipo técnico inmediatamente
- Error de WhatsApp API 401 (token expirado): pausar workflow y notificar
- Error de WhatsApp API 429 (rate limit): esperar 60s y reintentar ese mensaje
- Implementar nodo Error Trigger global que captura errores no manejados

## ESQUEMA ADICIONAL DE DB (incluir como comentario)
CREATE TABLE scheduler_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_name VARCHAR(100),
  appointments_found INTEGER DEFAULT 0,
  appointments_processed INTEGER DEFAULT 0,
  appointments_succeeded INTEGER DEFAULT 0,
  appointments_failed INTEGER DEFAULT 0,
  started_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
);

CREATE TABLE reminder_errors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id UUID,
  patient_phone VARCHAR(20),
  reminder_type VARCHAR(10), -- '24h' | '3h'
  error_response JSONB,
  retry_count INTEGER DEFAULT 0,
  resolved BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);

## CONSIDERACIONES DE PRODUCCIÓN
- El workflow debe ser idempotente: si se ejecuta dos veces seguidas no debe 
  enviar doble recordatorio (el flag reminder_24h_sent lo garantiza)
- Para multi-clínica: el JOIN con clinics permite usar el token y phone_number_id 
  correcto de cada clínica
- El LIMIT 100 previene procesar demasiados registros en una sola ejecución
- Si hay más de 100 citas en la ventana (poco probable), la siguiente ejecución 
  en 30 min las procesará

## OUTPUT ESPERADO
JSON completo importable en n8n. Este workflow no llama a ningún otro workflow 
(es autónomo). Todos los accesos son directos a Postgres y a la API de WhatsApp.