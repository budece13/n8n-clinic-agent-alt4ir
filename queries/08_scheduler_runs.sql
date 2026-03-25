-- =============================================================
-- TABLA: scheduler_runs
-- Log de cada ejecución de los workflows de recordatorios
-- Usado por WA-Reminder-24h-Scheduler y WA-Reminder-3h-Followup
-- =============================================================

CREATE TABLE IF NOT EXISTS scheduler_runs (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),

    -- 'WA-Reminder-24h' | 'WA-Reminder-3h'
    workflow_name           VARCHAR(100)    NOT NULL,

    appointments_found      INTEGER         NOT NULL DEFAULT 0,
    appointments_processed  INTEGER         NOT NULL DEFAULT 0,
    appointments_succeeded  INTEGER         NOT NULL DEFAULT 0,
    appointments_failed     INTEGER         NOT NULL DEFAULT 0,

    started_at              TIMESTAMP       NOT NULL DEFAULT NOW(),
    completed_at            TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_scheduler_runs_workflow   ON scheduler_runs (workflow_name);
CREATE INDEX IF NOT EXISTS idx_scheduler_runs_started    ON scheduler_runs (started_at);
