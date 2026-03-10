-- init.sql  –  runs automatically when the postgres container is first created

CREATE TABLE IF NOT EXISTS jobs (
  id           SERIAL PRIMARY KEY,
  job_id       VARCHAR(64)  NOT NULL UNIQUE,
  input        JSONB        NOT NULL,
  processed_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_jobs_job_id       ON jobs (job_id);
CREATE INDEX IF NOT EXISTS idx_jobs_processed_at ON jobs (processed_at DESC);

-- Read-only role for analytics / monitoring
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'readonly') THEN
    CREATE ROLE readonly;
  END IF;
END
$$;

GRANT CONNECT ON DATABASE mydatabase TO readonly;
GRANT USAGE  ON SCHEMA public   TO readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO readonly;
