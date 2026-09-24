// Package orders sends orders and retries transient failures with acme/retry.
package orders

import (
	"context"
	"time"

	"github.com/acme/retry"
)

// Submit sends an order, calling send up to five times.
func Submit(ctx context.Context, send func(context.Context) error) error {
	cfg := retry.DefaultConfig()
	cfg.MaxTries = 5
	cfg.Delay = time.Millisecond
	return retry.Do(ctx, cfg, func(ctx context.Context) error {
		return send(ctx)
	})
}

// Cancel cancels an order, calling send up to two times.
func Cancel(ctx context.Context, send func(context.Context) error) error {
	return retry.Do(ctx, retry.Config{MaxTries: 2, Delay: time.Millisecond}, func(ctx context.Context) error {
		return send(ctx)
	})
}
