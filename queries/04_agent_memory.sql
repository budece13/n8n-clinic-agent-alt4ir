-- =============================================================
-- TABLA: agent_memory
-- Historial de mensajes del agente IA por sesión
-- Usada por el nodo LangChain "Postgres Chat Memory"
-- =============================================================

CREATE TABLE IF NOT EXISTS agent_memory (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id              VARCHAR(100)    NOT NULL,
    messages                JSONB           NOT NULL DEFAULT '[]',
    created_at              TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agent_memory_session_id ON agent_memory (session_id);
CREATE INDEX IF NOT EXISTS idx_agent_memory_created_at ON agent_memory (created_at);
