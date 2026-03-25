-- =============================================================
-- TABLA: clinics
-- Configuración maestra de cada clínica
-- =============================================================

CREATE TABLE IF NOT EXISTS clinics (
    clinic_id               VARCHAR(100)    PRIMARY KEY,
    name                    VARCHAR(200)    NOT NULL,
    whatsapp_phone_number_id VARCHAR(100),
    timezone                VARCHAR(100)    NOT NULL DEFAULT 'Europe/Madrid',

    -- Integración con sistema de citas externo
    api_type                VARCHAR(50),    -- 'calendly' | 'google_calendar' | 'custom'
    api_url                 TEXT,
    api_key                 TEXT,

    -- Credenciales Calendly
    calendly_link           TEXT,
    calendly_token          TEXT,
    calendly_event_type_uuid VARCHAR(100),

    -- Credenciales Google Calendar
    google_calendar_id      VARCHAR(200),

    created_at              TIMESTAMP       NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_clinics_whatsapp ON clinics (whatsapp_phone_number_id);
