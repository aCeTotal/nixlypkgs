package database

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/pressly/goose/v3/lock"

	"cachepanel/migrations"
)

type Querier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

func Open(ctx context.Context, url string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(url)
	if err != nil {
		return nil, fmt.Errorf("parse database url: %w", err)
	}
	cfg.AfterConnect = registerEnums
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("connect to database: %w", err)
	}
	return pool, nil
}

func Migrate(ctx context.Context, pool *pgxpool.Pool) (err error) {
	db := stdlib.OpenDBFromPool(pool)
	defer func() { err = errors.Join(err, db.Close()) }()
	locker, err := lock.NewPostgresSessionLocker()
	if err != nil {
		return err
	}
	provider, err := goose.NewProvider(goose.DialectPostgres, db, migrations.FS, goose.WithSessionLocker(locker))
	if err != nil {
		return err
	}
	if _, err = provider.Up(ctx); err != nil {
		return err
	}
	pool.Reset()
	return nil
}

// Lets pgx encode enum arrays.
func registerEnums(ctx context.Context, conn *pgx.Conn) error {
	rows, err := conn.Query(ctx, `
		SELECT name FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace,
		     LATERAL (VALUES (t.typname::text), ('_' || t.typname)) AS v(name)
		WHERE t.typtype = 'e' AND n.nspname = 'public'`)
	if err != nil {
		return err
	}
	names, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil || len(names) == 0 {
		return err
	}
	types, err := conn.LoadTypes(ctx, names)
	if err != nil {
		return err
	}
	conn.TypeMap().RegisterTypes(types)
	return nil
}

// JSON scans one json value.
func JSON(ctx context.Context, db Querier, query string, args ...any) ([]byte, error) {
	var body []byte
	err := db.QueryRow(ctx, query, args...).Scan(&body)
	return body, err
}
