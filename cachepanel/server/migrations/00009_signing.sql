-- +goose Up
CREATE TABLE signing_cas (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject text NOT NULL,
    fingerprint text NOT NULL UNIQUE CHECK (fingerprint ~ '^[0-9a-f]{64}$'),
    cert_pem text NOT NULL,
    not_after timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    retired_at timestamptz
);

-- One CA signs at a time.
CREATE UNIQUE INDEX signing_cas_active ON signing_cas ((true)) WHERE retired_at IS NULL;

CREATE TYPE signature_kind AS ENUM ('module', 'efi');

CREATE TABLE signatures (
    file_hash text NOT NULL CHECK (file_hash ~ '^[0-9a-f]{64}$'),
    ca_id bigint NOT NULL REFERENCES signing_cas ON DELETE CASCADE,
    kind signature_kind NOT NULL,
    signature bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ca_id, file_hash)
);

ALTER TABLE trees ADD COLUMN signed_by bigint REFERENCES signing_cas;

-- +goose Down
ALTER TABLE trees DROP COLUMN signed_by;
DROP TABLE signatures;
DROP TYPE signature_kind;
DROP TABLE signing_cas;
