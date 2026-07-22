-- AEF2 PostgreSQL init — auto-runs once on first container start
-- Safe: skips creation if database already exists

SELECT 'AEF2: creating service databases...' AS status;

SELECT 'CREATE DATABASE ' || db || ' TEMPLATE template0 ENCODING ''UTF8'''
FROM unnest(ARRAY['n8n','affine','flowise','langfuse','mem0','litellm']) AS db
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = db)
\gexec

SELECT 'AEF2: databases ready.' AS status;
