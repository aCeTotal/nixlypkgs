-- +goose Up
CREATE TYPE upstream_state AS ENUM ('current', 'updating', 'failed');

-- What the tracker last saw; the source holds the pins.
CREATE TABLE upstreams (
    attr text PRIMARY KEY,
    latest_rev text,
    state upstream_state NOT NULL DEFAULT 'current',
    error text,
    checked_at timestamptz,
    committed_at timestamptz
);

-- +goose Down
DROP TABLE upstreams;
DROP TYPE upstream_state;
