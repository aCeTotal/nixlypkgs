-- +goose Up
CREATE TYPE eval_state AS ENUM ('evaluating', 'done', 'failed');
CREATE TYPE build_state AS ENUM ('pending', 'queued', 'building', 'cached', 'failed', 'cancelled');

CREATE TABLE commits (
    sha text PRIMARY KEY CHECK (sha ~ '^[0-9a-f]{40}$'),
    position bigint NOT NULL UNIQUE,
    subject text NOT NULL,
    author text NOT NULL,
    committed_at timestamptz NOT NULL,
    eval_state eval_state NOT NULL DEFAULT 'evaluating',
    eval_started_at timestamptz NOT NULL DEFAULT now(),
    eval_finished_at timestamptz,
    eval_error text,
    attrs integer NOT NULL DEFAULT 0,
    failed_attrs integer NOT NULL DEFAULT 0,
    changed integer NOT NULL DEFAULT 0
);

CREATE TABLE packages (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    attr text NOT NULL UNIQUE,
    auto_build boolean NOT NULL DEFAULT true,
    present boolean NOT NULL DEFAULT true,
    pinnable boolean NOT NULL DEFAULT false,
    eval_error text,
    expected_seconds integer,
    selected_version_id bigint
);

CREATE TABLE versions (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    package_id bigint NOT NULL REFERENCES packages ON DELETE CASCADE,
    drv_path text NOT NULL,
    name text NOT NULL,
    outputs jsonb NOT NULL,
    first_sha text NOT NULL REFERENCES commits,
    last_sha text NOT NULL REFERENCES commits,
    first_position bigint NOT NULL,
    last_position bigint NOT NULL,
    state build_state NOT NULL,
    priority boolean NOT NULL DEFAULT false,
    queued_at timestamptz,
    started_at timestamptz,
    finished_at timestamptz,
    closure_bytes bigint,
    error text,
    UNIQUE (package_id, drv_path)
);

CREATE INDEX versions_recent ON versions (package_id, last_position DESC);
CREATE INDEX versions_queue ON versions (priority DESC, last_position DESC, id) WHERE state = 'queued';
CREATE INDEX versions_building ON versions (drv_path) WHERE state = 'building';
CREATE INDEX versions_unfinished ON versions (first_position, last_position) WHERE state IN ('queued', 'building');
CREATE INDEX versions_finished ON versions (finished_at DESC) WHERE finished_at IS NOT NULL;
CREATE INDEX versions_span ON versions (first_position, last_position);

ALTER TABLE packages ADD CONSTRAINT packages_selected_version_fkey
    FOREIGN KEY (selected_version_id) REFERENCES versions ON DELETE SET NULL;
CREATE INDEX packages_selected ON packages (selected_version_id) WHERE selected_version_id IS NOT NULL;

CREATE TABLE watcher (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    paused boolean NOT NULL DEFAULT false,
    backfill_steps integer NOT NULL DEFAULT 0,
    backfill_done boolean NOT NULL DEFAULT false
);

INSERT INTO watcher DEFAULT VALUES;

-- +goose Down
DROP TABLE watcher;
ALTER TABLE packages DROP CONSTRAINT packages_selected_version_fkey;
DROP TABLE versions;
DROP TABLE packages;
DROP TABLE commits;
DROP TYPE build_state;
DROP TYPE eval_state;
