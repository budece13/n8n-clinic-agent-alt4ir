-- =============================================================
-- TABLA: conversation_sessions
-- Estado activo de cada conversación de WhatsApp
-- Una fila por número de teléfono (UPSERT en cada mensaje)
-- =============================================================

CREATE TABLE IF NOT EXISTS conversation_sessions (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    phone                   VARCHAR(20)     NOT NULL UNIQUE,
    clinic_id               VARCHAR(100),

    -- Contexto de la conversación en curso (JSON flexible)
    session_data            JSONB           NOT NULL DEFAULT '{}',

    -- Contexto de cita en proceso de creación
    appointment_context     JSONB           NOT NULL DEFAULT '{}',

    last_interaction        TIMESTAMP,
    updated_at              TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- Índice para limpiar sesiones expiradas (WHERE updated_at < NOW() - INTERVAL '24 hours')
CREATE INDEX IF NOT EXISTS idx_conversation_sessions_updated ON conversation_sessions (updated_at);
