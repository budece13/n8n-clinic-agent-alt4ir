-- =============================================================
-- TABLA: clinic_knowledge_base
-- Base de conocimiento de cada clínica para el agente RAG
-- Contiene horarios, servicios, precios, FAQs, etc.
-- =============================================================

CREATE TABLE IF NOT EXISTS clinic_knowledge_base (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    clinic_id               VARCHAR(100)    NOT NULL REFERENCES clinics (clinic_id),

    -- Tipo de contenido: 'horarios' | 'servicios' | 'precios' | 'faq' | 'ubicacion' | etc.
    kb_type                 VARCHAR(50)     NOT NULL,
    title                   VARCHAR(200),
    content                 TEXT            NOT NULL,

    -- Metadatos adicionales en formato libre
    metadata                JSONB           NOT NULL DEFAULT '{}',

    active                  BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMP       NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_knowledge_base_clinic ON clinic_knowledge_base (clinic_id, active);
CREATE INDEX IF NOT EXISTS idx_knowledge_base_type   ON clinic_knowledge_base (clinic_id, kb_type) WHERE active = TRUE;
