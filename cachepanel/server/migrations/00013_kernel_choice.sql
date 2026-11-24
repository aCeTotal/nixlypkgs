-- +goose Up
-- Kernels come from the source's catalogue.
ALTER TABLE profiles ALTER COLUMN kernel DROP DEFAULT;
ALTER TABLE profiles ALTER COLUMN kernel TYPE text USING kernel::text;
ALTER TABLE profiles ALTER COLUMN kernel SET DEFAULT 'performance';
DROP TYPE kernel;
UPDATE profiles SET kernel = 'server' WHERE platform = 'server' AND kernel = 'performance';
ALTER TABLE profiles ADD COLUMN kernel_settings jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(kernel_settings) = 'object');
-- Desktops kept madvise through the system module.
UPDATE profiles SET kernel_settings = '{"hugepages": "madvise"}' WHERE kernel = 'performance';

ALTER TABLE commits ADD COLUMN kernels jsonb;
CREATE INDEX commits_kernels ON commits (position DESC) WHERE kernels IS NOT NULL;

-- +goose Down
SELECT 1;
