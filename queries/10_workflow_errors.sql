-- =============================================================
-- TABLA: workflow_errors
-- Log genérico de errores de cualquier workflow n8n
-- Consolida los campos usados por todos los workflows:
--   - WA-Inbound-Orchestrator   → workflow, phone, payload
--   - WA-Reminder-*             → workflow, payload
--   - WA-Appointments-Manager   → workflow_name, node_name, input_data
-- =============================================================

CREATE TABLE IF NOT EXISTS workflow_errors (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Nombre del workflow (algunos usan 'workflow', otros 'workflow_name')
    workflow                VARCHAR(100),
    workflow_name           VARCHAR(100),

    -- Nodo donde ocurrió el error (WA-Appointments-Manager)
    node_name               VARCHAR(200),

    error_message           TEXT,

    -- Teléfono del paciente relacionado (si aplica)
    phone                   VARCHAR(20),

    -- Payload que causó el error (algunos usan 'payload', otros 'input_data')
    payload                 JSONB,
    input_data              JSONB,

    created_at              TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workflow_errors_workflow  ON workflow_errors (workflow);
CREATE INDEX IF NOT EXISTS idx_workflow_errors_name      ON workflow_errors (workflow_name);
CREATE INDEX IF NOT EXISTS idx_workflow_errors_created   ON workflow_errors (created_at);
CREATE INDEX IF NOT EXISTS idx_workflow_errors_phone     ON workflow_errors (phone) WHERE phone IS NOT NULL;
