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

-- v3: a short title for the city frontend; older reports borrow theirs from the description
ALTER TABLE reports ADD COLUMN IF NOT EXISTS title VARCHAR(100);
UPDATE reports SET title = LEFT(description, 100) WHERE title IS NULL;
ALTER TABLE reports ALTER COLUMN title SET NOT NULL;

-- v3: where the pin came from. ONSITE = the phone's GPS; REMOTE = placed by hand on the map
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'location_source') THEN
        CREATE TYPE location_source AS ENUM ('ONSITE', 'REMOTE');
    END IF;
END
$$;

-- Every report saved before v3 used the phone's GPS, so the default fills them in correctly
ALTER TABLE reports ADD COLUMN IF NOT EXISTS location_source location_source NOT NULL DEFAULT 'ONSITE';

-- Where the phone actually was for a REMOTE report (NULL for ONSITE, where it equals lat/long)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS device_long DOUBLE PRECISION;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS device_lat DOUBLE PRECISION;

-- v4: the state the report is in, so two cities with the same name stay apart.
-- Older reports start with the reporter's home state; geocoding replaces it with the real one.
ALTER TABLE reports ADD COLUMN IF NOT EXISTS state VARCHAR(100);
UPDATE reports r SET state = u.state FROM users u WHERE r.username = u.username AND r.state IS NULL;

-- v4: true once city/state came from the report's coordinates, false while they are the
-- reporter's home city/state (every older report, and any report the geocoder couldn't place)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS geocoded BOOLEAN NOT NULL DEFAULT false;

-- v4: failed geocoding tries; the nightly cleanup job stops retrying a report at its limit
ALTER TABLE reports ADD COLUMN IF NOT EXISTS geocode_attempts SMALLINT NOT NULL DEFAULT 0;

-- v4: a partial index holds only the rows matching its WHERE, so it stays tiny:
-- just the reports still waiting to be geocoded, in the order the cleanup job reads them
CREATE INDEX IF NOT EXISTS reports_ungeocoded_idx ON reports (created_at) WHERE geocoded = false;

-- v4: when a report last changed (status changes by the city, retries, validation)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;
UPDATE reports SET updated_at = created_at WHERE updated_at IS NULL;
ALTER TABLE reports ALTER COLUMN updated_at SET DEFAULT CURRENT_TIMESTAMP;

-- v4: which city each city staff account works for. Staff are created by an admin, not by
-- the sign-up trigger, so they have no users row and this table has no foreign key to it.
CREATE TABLE IF NOT EXISTS city_staff (
    username VARCHAR(100) PRIMARY KEY,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- v4: the city map's lookup. The expressions must match the query's exactly
-- (lower(trim(...))) or Postgres can't use the index.
CREATE INDEX IF NOT EXISTS reports_city_lookup_idx
    ON reports (lower(trim(state)), lower(trim(city)), status);
