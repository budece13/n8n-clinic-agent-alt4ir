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

Orden de construcción recomendado
Dile a Claude Code que los construya en este orden exacto para que las dependencias cuadren:
2 → 3 → 1 → 4 → 5
Primero los sub-workflows que el orquestador llama, luego el orquestador (con gestión de sesión integrada), y por último los schedulers independientes. Así en cada paso puedes importar el JSON en n8n y testear de forma aislada antes de conectar el siguiente.