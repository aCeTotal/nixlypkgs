-- +goose Up
-- Modules live in nixlyos/modules; profiles keep their choice.
ALTER TABLE profile_modules ADD COLUMN slug text;
UPDATE profile_modules pm SET slug = m.slug FROM modules m WHERE m.id = pm.module_id;
ALTER TABLE profile_modules DROP CONSTRAINT profile_modules_pkey;
ALTER TABLE profile_modules DROP COLUMN module_id;
ALTER TABLE profile_modules ALTER COLUMN slug SET NOT NULL;
ALTER TABLE profile_modules ADD PRIMARY KEY (profile_id, slug);
CREATE INDEX profile_modules_slug ON profile_modules (slug);
DROP TABLE module_revisions;
DROP TABLE modules;

-- +goose Down
SELECT 1;
