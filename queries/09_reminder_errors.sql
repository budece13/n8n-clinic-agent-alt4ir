-- =============================================================
-- TABLA: reminder_errors
-- Fallos individuales al enviar recordatorios por WhatsApp
-- Permite reintentar o revisar manualmente los envíos fallidos
-- =============================================================

CREATE TABLE IF NOT EXISTS reminder_errors (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id          UUID            REFERENCES appointments (id),
    patient_phone           VARCHAR(20),

    -- '24h' | '3h'
    reminder_type           VARCHAR(10)     NOT NULL,

    -- Respuesta de error completa de la API de WhatsApp
    error_response          JSONB,

    retry_count             INTEGER         NOT NULL DEFAULT 0,
    resolved                BOOLEAN         NOT NULL DEFAULT FALSE,

    created_at              TIMESTAMP       NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_reminder_errors_type CHECK (reminder_type IN ('24h', '3h'))
);

CREATE INDEX IF NOT EXISTS idx_reminder_errors_appointment  ON reminder_errors (appointment_id);
CREATE INDEX IF NOT EXISTS idx_reminder_errors_type         ON reminder_errors (reminder_type, created_at);
CREATE INDEX IF NOT EXISTS idx_reminder_errors_unresolved   ON reminder_errors (resolved, created_at) WHERE resolved = FALSE;
