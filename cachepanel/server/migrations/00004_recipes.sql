-- +goose Up
CREATE TYPE recipe_state AS ENUM ('importing', 'draft', 'building', 'ready', 'failed', 'published');

CREATE TABLE recipes (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    attr text UNIQUE CHECK (attr ~ '^[A-Za-z_][A-Za-z0-9_-]*$'),
    origin jsonb NOT NULL,
    spec jsonb,
    state recipe_state NOT NULL DEFAULT 'importing',
    error text,
    report jsonb NOT NULL DEFAULT '{}',
    output text,
    published_sha text,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX recipes_updated ON recipes (updated_at DESC);

CREATE TABLE recipe_files (
    recipe_id bigint NOT NULL REFERENCES recipes ON DELETE CASCADE,
    name text NOT NULL CHECK (name ~ '^[A-Za-z0-9_+-][A-Za-z0-9._+-]*$'),
    content bytea NOT NULL,
    PRIMARY KEY (recipe_id, name)
);

-- +goose Down
DROP TABLE recipe_files;
DROP TABLE recipes;
DROP TYPE recipe_state;
