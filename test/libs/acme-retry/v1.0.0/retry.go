// Package retry runs an operation again when it fails.
package retry

import (
	"context"
	"errors"
	"time"
)

// Config says how often and how far apart to call the operation.
type Config struct {
	// MaxTries is the total number of calls, including the first one.
	MaxTries int
	// Delay is the wait between two calls.
	Delay time.Duration
}

// DefaultConfig calls the operation up to three times, 100ms apart.
func DefaultConfig() Config {
	return Config{MaxTries: 3, Delay: 100 * time.Millisecond}
}

// Do calls fn until it returns nil, the tries run out, or ctx is done.
// It returns the last error from fn.
func Do(ctx context.Context, cfg Config, fn func(ctx context.Context) error) error {
	if cfg.MaxTries < 1 {
		return errors.New("retry: MaxTries must be at least 1")
	}
	var err error
	for i := 0; i < cfg.MaxTries; i++ {
		if err = fn(ctx); err == nil {
			return nil
		}
		if i == cfg.MaxTries-1 {
			break
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(cfg.Delay):
		}
	}
	return err
}
