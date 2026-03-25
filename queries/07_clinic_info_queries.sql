-- =============================================================
-- TABLA: clinic_info_queries
-- Log histórico de preguntas de pacientes sobre la clínica
-- Útil para analítica y para mejorar la knowledge base
-- =============================================================

CREATE TABLE IF NOT EXISTS clinic_info_queries (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    clinic_id               VARCHAR(100)    REFERENCES clinics (clinic_id),
    question                TEXT,
    intent_category         VARCHAR(50),
    answer                  TEXT,
    created_at              TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_clinic_info_queries_clinic   ON clinic_info_queries (clinic_id);
CREATE INDEX IF NOT EXISTS idx_clinic_info_queries_created  ON clinic_info_queries (created_at);
CREATE INDEX IF NOT EXISTS idx_clinic_info_queries_intent   ON clinic_info_queries (intent_category);
