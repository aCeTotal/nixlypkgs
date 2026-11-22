-- +goose Up
CREATE TYPE platform AS ENUM ('desktop', 'htpc');
CREATE TYPE check_state AS ENUM ('pending', 'running', 'passed', 'failed', 'skipped');

CREATE TABLE catalog_categories (
    name text PRIMARY KEY,
    title text NOT NULL,
    position integer NOT NULL
);

CREATE TABLE catalog_modules (
    name text PRIMARY KEY,
    category text NOT NULL,
    position integer NOT NULL,
    title text NOT NULL,
    path text NOT NULL,
    x86_only boolean NOT NULL DEFAULT false,
    required boolean NOT NULL DEFAULT false,
    automatic boolean NOT NULL DEFAULT false,
    defaults text[] NOT NULL DEFAULT '{}',
    present boolean NOT NULL DEFAULT true
);

CREATE INDEX catalog_modules_order ON catalog_modules (category, position);

CREATE TABLE modules (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]{0,62}$'),
    title text NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
    description text NOT NULL DEFAULT '',
    source text NOT NULL,
    revision integer NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE module_revisions (
    module_id bigint NOT NULL REFERENCES modules ON DELETE CASCADE,
    revision integer NOT NULL,
    source text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (module_id, revision)
);

CREATE TABLE trees (
    hash text PRIMARY KEY CHECK (hash ~ '^[0-9a-f]{64}$'),
    archive bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE profiles (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL UNIQUE CHECK (name ~ '^[a-z0-9][a-z0-9-]{0,31}$'),
    title text NOT NULL CHECK (length(title) BETWEEN 1 AND 80),
    description text NOT NULL DEFAULT '',
    platform platform NOT NULL,
    pinned_sha text REFERENCES commits ON DELETE SET NULL,
    catalog text[] NOT NULL DEFAULT '{}',
    packages text[] NOT NULL DEFAULT '{}',
    candidate_tree text REFERENCES trees,
    candidate_rev text REFERENCES commits ON DELETE SET NULL,
    published_tree text REFERENCES trees,
    published_rev text REFERENCES commits ON DELETE SET NULL,
    published_at timestamptz,
    check_state check_state NOT NULL DEFAULT 'pending',
    check_error text,
    checked_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX profiles_pinned ON profiles (pinned_sha) WHERE pinned_sha IS NOT NULL;
CREATE INDEX profiles_candidate_tree ON profiles (candidate_tree);
CREATE INDEX profiles_published_tree ON profiles (published_tree);

CREATE TABLE profile_modules (
    profile_id bigint NOT NULL REFERENCES profiles ON DELETE CASCADE,
    module_id bigint NOT NULL REFERENCES modules ON DELETE RESTRICT,
    PRIMARY KEY (profile_id, module_id)
);

CREATE INDEX profile_modules_module ON profile_modules (module_id);

-- +goose Down
DROP TABLE profile_modules;
DROP TABLE profiles;
DROP TABLE trees;
DROP TABLE module_revisions;
DROP TABLE modules;
DROP TABLE catalog_modules;
DROP TABLE catalog_categories;
DROP TYPE check_state;
DROP TYPE platform;
