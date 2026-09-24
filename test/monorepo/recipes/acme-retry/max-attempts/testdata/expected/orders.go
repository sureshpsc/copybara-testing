package orders

import "github.com/acme/retry/v2"

func config() retry.Config {
	cfg := retry.Config{MaxAttempts: 2}
	cfg.MaxAttempts = 5
	return cfg
}
