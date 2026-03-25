-- =============================================================
-- TABLA: appointments
-- Citas médicas (tabla central del sistema)
-- =============================================================

CREATE TABLE IF NOT EXISTS appointments (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    clinic_id               VARCHAR(100)    NOT NULL REFERENCES clinics (clinic_id),
    patient_phone           VARCHAR(20)     NOT NULL,
    patient_name            VARCHAR(200),
    service                 VARCHAR(200),
    datetime                TIMESTAMP       NOT NULL,

    -- Estado del ciclo de vida de la cita
    status                  VARCHAR(20)     NOT NULL DEFAULT 'scheduled',
                                            -- 'scheduled' | 'confirmed' | 'cancelled' | 'rescheduled'

    -- IDs en sistemas externos (Calendly, Google Calendar, HIS...)
    external_id             VARCHAR(200),
    external_calendar_id    VARCHAR(200),

    -- Control de recordatorios
    reminder_24h_sent       BOOLEAN         NOT NULL DEFAULT FALSE,
    reminder_24h_sent_at    TIMESTAMP,
    reminder_3h_sent        BOOLEAN         NOT NULL DEFAULT FALSE,
    reminder_3h_sent_at     TIMESTAMP,
    reminder_responded      BOOLEAN         NOT NULL DEFAULT FALSE,

    created_at              TIMESTAMP       NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMP       NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_appointments_status
        CHECK (status IN ('scheduled', 'confirmed', 'cancelled', 'rescheduled'))
);

-- Índices para las consultas más frecuentes de los workflows
CREATE INDEX IF NOT EXISTS idx_appointments_patient_phone  ON appointments (patient_phone);
CREATE INDEX IF NOT EXISTS idx_appointments_clinic_id      ON appointments (clinic_id);
CREATE INDEX IF NOT EXISTS idx_appointments_datetime       ON appointments (datetime);
CREATE INDEX IF NOT EXISTS idx_appointments_status         ON appointments (status);

-- Índice compuesto para la query de recordatorios 24h
CREATE INDEX IF NOT EXISTS idx_appointments_reminder_24h
    ON appointments (status, reminder_24h_sent, datetime)
    WHERE status IN ('scheduled', 'confirmed') AND reminder_24h_sent = FALSE;

-- Índice compuesto para la query de recordatorios 3h
CREATE INDEX IF NOT EXISTS idx_appointments_reminder_3h
    ON appointments (status, reminder_24h_sent, reminder_responded, reminder_3h_sent, datetime)
    WHERE status IN ('scheduled', 'confirmed')
      AND reminder_24h_sent = TRUE
      AND reminder_responded = FALSE
      AND reminder_3h_sent = FALSE;
