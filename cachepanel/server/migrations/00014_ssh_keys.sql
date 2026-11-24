-- +goose Up
CREATE TABLE ssh_keys (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL CHECK (name <> ''),
    key_type text NOT NULL,
    key_data text NOT NULL CHECK (key_data ~ '^[A-Za-z0-9+/]+=*$'),
    fingerprint text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- +goose Down
DROP TABLE ssh_keys;
