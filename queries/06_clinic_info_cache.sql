-- =============================================================
-- TABLA: clinic_info_cache
-- Caché de respuestas a preguntas frecuentes (TTL: 6 horas)
-- Evita llamadas repetidas a la IA para preguntas idénticas
-- =============================================================

CREATE TABLE IF NOT EXISTS clinic_info_cache (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    clinic_id               VARCHAR(100)    NOT NULL REFERENCES clinics (clinic_id),

    -- Pregunta normalizada: LOWER(TRIM(pregunta_original))
    normalized_question     TEXT            NOT NULL,
    answer                  TEXT,
    intent_category         VARCHAR(50),

    created_at              TIMESTAMP       NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_clinic_info_cache UNIQUE (clinic_id, normalized_question)
);

-- Índice para limpiar entradas expiradas (WHERE created_at < NOW() - INTERVAL '6 hours')
CREATE INDEX IF NOT EXISTS idx_clinic_info_cache_created ON clinic_info_cache (created_at);
