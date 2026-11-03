CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) NOT NULL,
    firstname VARCHAR(100) NOT NULL,
    lastname VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'status') THEN
        CREATE TYPE status AS ENUM ('PENDING', 'CONFIRMED', 'REJECTED', 'COMPLETED', 'ACTIVE');
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY,
    username VARCHAR(100) REFERENCES users(username),
    imagepath VARCHAR(500) NOT NULL,
    long DOUBLE PRECISION NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    confidencelvl DOUBLE PRECISION NOT NULL,
    description VARCHAR(200) NOT NULL,
    status status NOT NULL DEFAULT 'PENDING',
    city VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- PENDING reports are saved before the model has scored them
ALTER TABLE reports ALTER COLUMN confidencelvl DROP NOT NULL;

CREATE INDEX IF NOT EXISTS reports_status_created_at_idx ON reports (status, created_at);
