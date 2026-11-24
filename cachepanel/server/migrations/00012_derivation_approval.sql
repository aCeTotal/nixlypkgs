-- +goose Up
-- The version stable machines get.
ALTER TABLE packages ADD COLUMN stable_version_id bigint REFERENCES versions ON DELETE SET NULL;
CREATE INDEX packages_stable_version ON packages (stable_version_id) WHERE stable_version_id IS NOT NULL;

-- Which version each pin is.
ALTER TABLE trees ADD COLUMN pins jsonb;

-- Stable's own approved base and check.
ALTER TABLE profiles
    ADD COLUMN base_tree text REFERENCES trees,
    ADD COLUMN base_rev text REFERENCES commits ON DELETE SET NULL,
    ADD COLUMN stable_candidate_tree text REFERENCES trees,
    ADD COLUMN stable_check_state check_state,
    ADD COLUMN stable_check_error text;
CREATE INDEX profiles_base_tree ON profiles (base_tree);
CREATE INDEX profiles_stable_candidate_tree ON profiles (stable_candidate_tree);

UPDATE profiles SET base_tree = stable_tree, base_rev = stable_rev WHERE stable_tree IS NOT NULL;

-- +goose Down
ALTER TABLE profiles
    DROP COLUMN base_tree,
    DROP COLUMN base_rev,
    DROP COLUMN stable_candidate_tree,
    DROP COLUMN stable_check_state,
    DROP COLUMN stable_check_error;
ALTER TABLE trees DROP COLUMN pins;
ALTER TABLE packages DROP COLUMN stable_version_id;
