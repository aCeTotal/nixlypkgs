package ratelimit

import (
	"context"
	"sync"
	"time"
)

// Limiter counts hits per window.
type Limiter struct {
	limit  int
	window time.Duration

	mu   sync.Mutex
	hits map[string]bucket
}

type bucket struct {
	count int
	reset time.Time
}

func New(limit int, window time.Duration) *Limiter {
	return &Limiter{limit: limit, window: window, hits: map[string]bucket{}}
}

func (l *Limiter) Allow(key string) bool {
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()
	current, found := l.hits[key]
	if !found || now.After(current.reset) {
		current = bucket{reset: now.Add(l.window)}
	}
	current.count++
	l.hits[key] = current
	return current.count <= l.limit
}

// Run drops expired buckets.
func (l *Limiter) Run(ctx context.Context) {
	ticker := time.NewTicker(l.window)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-ticker.C:
			l.sweep(now)
		}
	}
}

func (l *Limiter) sweep(now time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	for key, current := range l.hits {
		if now.After(current.reset) {
			delete(l.hits, key)
		}
	}
}
