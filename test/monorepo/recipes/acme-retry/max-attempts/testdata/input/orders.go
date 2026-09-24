package orders

import "github.com/acme/retry/v2"

func config() retry.Config {
	cfg := retry.Config{MaxTries: 2}
	cfg.MaxTries = 5
	return cfg
}
