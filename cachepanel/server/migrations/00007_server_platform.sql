-- +goose NO TRANSACTION
-- +goose Up
ALTER TYPE platform ADD VALUE IF NOT EXISTS 'server';
