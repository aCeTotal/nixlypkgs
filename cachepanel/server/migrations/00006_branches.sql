-- +goose Up
ALTER TABLE profiles RENAME COLUMN published_tree TO stable_tree;
ALTER TABLE profiles RENAME COLUMN published_rev TO stable_rev;
ALTER TABLE profiles RENAME COLUMN published_at TO stable_at;
ALTER INDEX profiles_published_tree RENAME TO profiles_stable_tree;

ALTER TABLE profiles
    ADD COLUMN testing_tree text REFERENCES trees,
    ADD COLUMN testing_rev text REFERENCES commits ON DELETE SET NULL,
    ADD COLUMN testing_at timestamptz;

UPDATE profiles SET testing_tree = stable_tree, testing_rev = stable_rev, testing_at = stable_at;

CREATE INDEX profiles_testing_tree ON profiles (testing_tree);

-- +goose Down
DROP INDEX profiles_testing_tree;
ALTER TABLE profiles DROP COLUMN testing_at, DROP COLUMN testing_rev, DROP COLUMN testing_tree;
ALTER INDEX profiles_stable_tree RENAME TO profiles_published_tree;
ALTER TABLE profiles RENAME COLUMN stable_at TO published_at;
ALTER TABLE profiles RENAME COLUMN stable_rev TO published_rev;
ALTER TABLE profiles RENAME COLUMN stable_tree TO published_tree;
