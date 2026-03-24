Eres un experto en n8n y debes construir un workflow de producción en formato JSON 
importable directamente en n8n (versión 1.x)(Impórtalo tú de manera autónoma en mi instancia de n8n con uso de mi api key disponible en .mcp.json). El workflow se llama 
"WA-Reminder-3h-Followup-Scheduler" y es un proceso autónomo que envía un 
recordatorio de seguimiento 3 horas antes de la cita, pero SOLO a aquellos 
pacientes que no respondieron al recordatorio de 24 horas previo.

## FUNCIÓN DE ESTE WORKFLOW
Opera de forma completamente independiente. Su lógica central es: detectar citas 
que se aproximan en ~3 horas, cuyo recordatorio de 24h fue enviado pero el paciente 
no respondió, y enviar un segundo mensaje más urgente. Tiene en cuenta que si el 
paciente ya respondió (confirmó o canceló) NO debe recibir este segundo recordatorio.

## TRIGGER
Nodo: Schedule Trigger
- Intervalo: cada 15 minutos (más frecuente que el de 24h por la ventana más estrecha)
- Timezone: Europe/Madrid
- Activo las 24h (hay citas a primera hora de la mañana)

## NODOS Y LÓGICA COMPLETA

### Nodo 1: "Fetch Appointments for 3h Followup" (Postgres Node)
Esta es la query más crítica del workflow. Condiciones estrictas:

SELECT 
  a.id as appointment_id,
  a.patient_phone,
  a.patient_name,
  a.service,
  a.datetime,
  a.clinic_id,
  a.reminder_24h_sent_at,
  c.name as clinic_name,
  c.timezone,
  c.whatsapp_phone_number_id,
  c.whatsapp_token,
  c.cancellation_policy_hours
FROM appointments a
JOIN clinics c ON a.clinic_id = c.clinic_id
WHERE 
  a.status IN ('scheduled', 'confirmed')
  AND a.reminder_24h_sent = true          -- el de 24h SÍ fue enviado
  AND a.reminder_responded = false         -- pero NO hubo respuesta
  AND a.reminder_3h_sent = false           -- y este de 3h aún NO fue enviado
  AND a.datetime >= NOW() + INTERVAL '2 hours 30 minutes'
  AND a.datetime <= NOW() + INTERVAL '3 hours 30 minutes'
ORDER BY a.datetime ASC
LIMIT 100;

### Nodo 2: "Check if Any Appointments Found" (IF Node)
Condición: {{ $json.length > 0 }}
- Si NO: → Log vacío y terminar
- Si SÍ: → Continuar

### Nodo 3: "Log Run Start" (Postgres Node)
INSERT INTO scheduler_runs (workflow_name, appointments_found, started_at)
VALUES ('WA-Reminder-3h', {{ count }}, NOW()) RETURNING id;

### Nodo 4: "Split Into Items" (Item Lists / Split Batches)
Procesa cada cita individualmente. Batch size: 1

### Nodo 5: "Format Urgency Message" (Code Node)
El mensaje de 3h debe ser más directo y urgente que el de 24h, 
pero seguir siendo amable:

const appt = items[0].json;
const hora = new Date(appt.datetime).toLocaleTimeString('es-ES', { 
  hour: '2-digit', minute: '2-digit', timeZone: appt.timezone 
});
const nombre = appt.patient_name ? appt.patient_name : 'te';
const horasAntes = Math.round((new Date(appt.datetime) - new Date()) / 3600000);

// Calcular si aún es posible cancelar sin penalización
const policy = appt.cancellation_policy_hours || 24;
const horasRestantes = (new Date(appt.datetime) - new Date()) / 3600000;
const canCancelFree = horasRestantes >= policy;

const cancelNote = canCancelFree 
  ? '❌ Responde *NO* si necesitas cancelar'
  : `⚠️ Ten en cuenta que las cancelaciones con menos de ${policy}h pueden 
     tener cargo según nuestra política`;

const message = `⏰ Recordatorio importante, ${nombre}

Tu cita en *${appt.clinic_name}* es *hoy a las ${hora}* (en aproximadamente 
${horasAntes} horas).

💊 Servicio: ${appt.service}

No hemos recibido tu confirmación. ¿Sigues viniendo?

✅ Responde *SÍ* para confirmar
${cancelNote}
🔄 Responde *CAMBIAR* si necesitas otra fecha

Si no puedes asistir, por favor avísanos para liberar el horario 🙏`;

return [{ json: { ...appt, message_text: message } }];

### Nodo 6: "Send WhatsApp 3h Reminder" (HTTP Request Node)
- URL: https://graph.facebook.com/v18.0/{{ $json.whatsapp_phone_number_id }}/messages
- Method: POST
- Headers: Authorization: Bearer {{ $json.whatsapp_token }}
- Body:
{
  "messaging_product": "whatsapp",
  "to": "{{ $json.patient_phone }}",
  "type": "text",
  "text": { "body": "{{ $json.message_text }}" }
}
- Continue on fail: true
- Timeout: 10 segundos

### Nodo 7: "Check Send Success" (IF Node)
Condición: HTTP status 200 o 201

- ÉXITO → Nodo 8: "Mark 3h Reminder Sent"
- FALLO → Nodo "Log 3h Send Error"

### Nodo 8: "Mark 3h Reminder Sent in DB" (Postgres Node)
UPDATE appointments 
SET 
  reminder_3h_sent = true,
  reminder_3h_sent_at = NOW(),
  updated_at = NOW()
WHERE id = $appointment_id;

### Nodo "Log 3h Send Error" (Postgres Node)
INSERT INTO reminder_errors (
  appointment_id, patient_phone, reminder_type,
  error_response, created_at
) VALUES ($appointment_id, $phone, '3h', $error::jsonb, NOW());

Adicionalmente, si es el segundo intento fallido para esta cita, 
enviar notificación al equipo de la clínica por email.

### Nodo 9: "Rate Limit Delay" (Wait Node)
- 500ms entre mensajes

### Nodo 10: "Update Clinic Alert" (IF Node + HTTP Request)
Condición adicional de negocio: si faltan menos de 2h para la cita y 
el paciente aún no confirma tras el recordatorio de 3h → notificar a la 
clínica internamente (email o Slack) para que puedan reasignar el slot 
si es necesario.

Condición: (datetime - NOW()) < '2 hours' AND reminder_responded = false
→ HTTP Request a webhook de notificación interna (Slack, email via SMTP, etc.)
Body: "Paciente {{ patient_name }} ({{ phone }}) no ha confirmado su cita 
de {{ service }} a las {{ hora }}. Considera liberar el slot."

### Nodo 11: "Log Run Complete" (Postgres Node)
UPDATE scheduler_runs SET 
  appointments_processed = {{ processed }},
  appointments_succeeded = {{ succeeded }},
  appointments_failed = {{ failed }},
  completed_at = NOW()
WHERE id = {{ runId }};

## DIFERENCIAS CLAVE VS EL WORKFLOW DE 24H
1. La query filtra ADICIONALMENTE por reminder_responded = false 
   (no molestar a quien ya confirmó)
2. El mensaje es más urgente en tono
3. Se ejecuta cada 15 min (ventana más estrecha)
4. Incluye lógica de política de cancelación para informar al paciente 
   si hay penalización
5. Incluye alerta interna a la clínica si se acerca la cita sin confirmación

## CASOS EDGE IMPORTANTES (comentar en el código)
- Si el paciente responde justo entre la ejecución del scheduler y el envío:
  La query protege esto con reminder_responded = false, pero hay una pequeña 
  race condition. Mitigación: añadir SELECT FOR UPDATE en la query o usar 
  transacciones si el volumen lo requiere.
- Citas canceladas en el último momento: el WHERE status IN ('scheduled','confirmed') 
  las excluye automáticamente.
- Zona horaria: todas las comparaciones de datetime deben hacerse en UTC en Postgres, 
  el formateo para el usuario usa el timezone de la clínica.

## OUTPUT ESPERADO
JSON completo importable en n8n. Idempotente, tolerante a fallos parciales, 
con logging completo de cada ejecución para auditoría. 
Sin dependencias de otros workflows (completamente autónomo).