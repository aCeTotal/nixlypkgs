-- +goose Up
-- What each branch's release holds in the cache.
ALTER TABLE profiles
    ADD COLUMN testing_paths integer,
    ADD COLUMN testing_bytes bigint,
    ADD COLUMN stable_paths integer,
    ADD COLUMN stable_bytes bigint;

-- +goose Down
ALTER TABLE profiles
    DROP COLUMN testing_paths,
    DROP COLUMN testing_bytes,
    DROP COLUMN stable_paths,
    DROP COLUMN stable_bytes;
