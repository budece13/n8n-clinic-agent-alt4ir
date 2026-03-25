-- =============================================================
-- INIT: Creación completa del esquema para n8n-clinic-agent
-- PostgreSQL 16
--
-- Orden de ejecución (respeta dependencias de foreign keys):
--   1. clinics              → tabla maestra, sin dependencias
--   2. appointments         → depende de clinics
--   3. conversation_sessions
--   4. agent_memory
--   5. clinic_knowledge_base → depende de clinics
--   6. clinic_info_cache     → depende de clinics
--   7. clinic_info_queries   → depende de clinics
--   8. scheduler_runs
--   9. reminder_errors       → depende de appointments
--  10. workflow_errors
--
-- Uso:
--   psql -U <usuario> -d <base_de_datos> -f 00_init_all.sql
-- =============================================================

\echo '>>> [01/10] Creando tabla clinics...'
\ir 01_clinics.sql

\echo '>>> [02/10] Creando tabla appointments...'
\ir 02_appointments.sql

\echo '>>> [03/10] Creando tabla conversation_sessions...'
\ir 03_conversation_sessions.sql

\echo '>>> [04/10] Creando tabla agent_memory...'
\ir 04_agent_memory.sql

\echo '>>> [05/10] Creando tabla clinic_knowledge_base...'
\ir 05_clinic_knowledge_base.sql

\echo '>>> [06/10] Creando tabla clinic_info_cache...'
\ir 06_clinic_info_cache.sql

\echo '>>> [07/10] Creando tabla clinic_info_queries...'
\ir 07_clinic_info_queries.sql

\echo '>>> [08/10] Creando tabla scheduler_runs...'
\ir 08_scheduler_runs.sql

\echo '>>> [09/10] Creando tabla reminder_errors...'
\ir 09_reminder_errors.sql

\echo '>>> [10/10] Creando tabla workflow_errors...'
\ir 10_workflow_errors.sql

\echo '>>> Esquema creado correctamente.'
