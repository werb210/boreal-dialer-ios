ALTER TABLE call_sessions
ADD COLUMN IF NOT EXISTS recording_sid text,
ADD COLUMN IF NOT EXISTS recording_url text,
ADD COLUMN IF NOT EXISTS recording_duration integer;

CREATE INDEX IF NOT EXISTS idx_call_sessions_client_id
ON call_sessions(client_id);
