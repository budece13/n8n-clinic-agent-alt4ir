Eres un agente con acceso MCP a mi instancia de n8n. Vas a adaptar los workflows
que integran con la API Django de una app de clínica ("auto-clinic"), tras un
cambio en el backend en el sistema de citas y confirmaciones.

NO cambies credenciales, webhooks de Meta/WhatsApp, ni nada fuera de los nodos que
llaman a la API de citas. Primero INSPECCIONA y hazme un plan; aplica los cambios
solo cuando te lo confirme.

## Paso 1 — Inventario
Lista los workflows y localiza todos los nodos HTTP Request que llaman a la API
Django de citas. Busca llamadas a estos endpoints:
- POST   /api/appointments/
- GET    /api/appointments/available-slots/
- GET    /api/appointments/pending-reminders/
- PATCH  /api/appointments/{id}/ (revisa que no haya ningun status=cancelled)
- POST   /api/appointments/{id}/confirm/
- POST   /api/public/appointments/{token}/confirm/
- POST   /api/public/appointments/{token}/cancel/
Para cada uno, dime en qué workflow y nodo está y qué hace con la respuesta.

## Paso 2 — Cambios a aplicar

Contexto del nuevo modelo: una cita creada por el agente NACE "pending" y bloquea
el hueco, pero queda PENDIENTE DE VALIDACIÓN por la clínica. Confirmar una cita
("ponerla en firme") es AHORA competencia EXCLUSIVA del staff desde su panel web.
El agente ya no confirma citas.

1. CREAR CITA (POST /api/appointments/)
   - El payload no cambia (sin `professional`, Django lo auto-asigna).
   - Nuevo error posible: HTTP 400 con { "code": "slot_unavailable", "message": ... }.
     Ocurre cuando el hueco se ocupó entre que se ofreció y se intentó reservar.
     Añade una rama que maneje ese `code` y muestre el `message` al paciente tal
     cual (ya viene redactado para él: "Ese hueco ya no está disponible, elige
     otra hora"). Trátalo igual que los otros errores de dominio
     (`no_professional_available`, `professional_unavailable`), que comparten la
     forma { code, message, details } y el 400.

2. RESPUESTA DEL PACIENTE AL RECORDATORIO (POST /api/public/appointments/{token}/confirm/)
   - La URL, el método y la forma de la respuesta (200 + cita) NO cambian.
   - PERO ahora esta llamada YA NO cambia el estado de la cita: solo registra que
     el paciente asistirá. Elimina cualquier lógica que dependa de que la
     respuesta traiga `status == "confirmed"` tras el "SÍ". El mensaje de
     WhatsApp al paciente ("¡confirmada, te esperamos!") sigue siendo válido.
   - La rama del "NO" (POST .../cancel/) no cambia: sigue cancelando.

3. RECORDATORIOS (GET /api/appointments/pending-reminders/?type=24h|3h)
   - La respuesta { results, count } no cambia de forma.
   - Ahora solo devuelve citas que la clínica YA confirmó. Una cita "pending" (aún
     sin validar por el staff) no genera recordatorio. No hace falta cambiar la
     llamada, pero si algún nodo asumía que las "pending" recibían recordatorio,
     ajústalo: ya no es así.

4. EL AGENTE NO CONFIRMA CITAS (importante)
   - Elimina cualquier nodo o paso que intente confirmar una cita por la API:
     tanto `POST /api/appointments/{id}/confirm/` (ahora responde 403 con la
     Api-Key del agente) como `PATCH /api/appointments/{id}/` con
     { "status": "confirmed" } (ahora responde 400). Ambas vías están cerradas a
     propósito: confirmar es solo del staff desde el panel.

5. CAMPOS INTERNOS
   - Si algún nodo lee o envía los campos `source`, `patient_confirmed_at` o
     `hold_expires_at`: quítalos. Ya no forman parte del contrato (no se
     devuelven ni se pueden escribir).

6. available-slots
   - Sin cambios de contrato. Solo un aviso: ahora un hueco ya reservado (aunque
     esté "pending") deja de ofrecerse, lo que evita reservas duplicadas. No
     requiere cambios.

## Paso 3 — Reporte
Antes de aplicar, muéstrame el plan: por cada workflow/nodo, qué cambiarás y por
qué. Tras mi visto bueno, aplica los cambios y dame un resumen de lo modificado.
