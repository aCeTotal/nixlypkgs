-- +goose Up
CREATE TABLE panel_update (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    enabled boolean NOT NULL DEFAULT true
);

INSERT INTO panel_update DEFAULT VALUES;

-- +goose Down
DROP TABLE panel_update;
