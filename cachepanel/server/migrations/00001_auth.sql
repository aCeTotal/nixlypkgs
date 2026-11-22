-- +goose Up
CREATE TABLE users (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username text NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9_.-]{1,64}$'),
    password_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    password_changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sessions (
    token_hash bytea PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users ON DELETE CASCADE,
    csrf text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL
);

CREATE INDEX sessions_user ON sessions (user_id);
CREATE INDEX sessions_expiry ON sessions (expires_at);

-- +goose Down
DROP TABLE sessions;
DROP TABLE users;
