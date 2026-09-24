// Package retry runs an operation again when it fails.
//
// Breaking changes from v1:
//   - the module path is github.com/acme/retry/v2
//   - Config.MaxTries is now Config.MaxAttempts
//   - DefaultConfig is now Default
//   - the function passed to Do also receives the attempt number, starting at 1
package retry

import (
	"context"
	"errors"
	"time"
)

// Config says how often and how far apart to call the operation.
type Config struct {
	// MaxAttempts is the total number of calls, including the first one.
	MaxAttempts int
	// Delay is the wait between two calls.
	Delay time.Duration
}

// Default calls the operation up to three times, 100ms apart.
func Default() Config {
	return Config{MaxAttempts: 3, Delay: 100 * time.Millisecond}
}

type permanent struct{ err error }

func (p permanent) Error() string { return p.err.Error() }
func (p permanent) Unwrap() error { return p.err }

// Permanent wraps err so Do returns it at once instead of calling again.
func Permanent(err error) error {
	if err == nil {
		return nil
	}
	return permanent{err}
}

// Do calls fn until it returns nil, a Permanent error, the attempts run out, or ctx is done.
// attempt is 1 for the first call. It returns the last error from fn.
func Do(ctx context.Context, cfg Config, fn func(ctx context.Context, attempt int) error) error {
	if cfg.MaxAttempts < 1 {
		return errors.New("retry: MaxAttempts must be at least 1")
	}
	var err error
	for attempt := 1; attempt <= cfg.MaxAttempts; attempt++ {
		if err = fn(ctx, attempt); err == nil {
			return nil
		}
		var p permanent
		if errors.As(err, &p) {
			return p.err
		}
		if attempt == cfg.MaxAttempts {
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
