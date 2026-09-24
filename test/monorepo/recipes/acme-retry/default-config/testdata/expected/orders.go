package orders

import "github.com/acme/retry/v2"

func config() retry.Config {
	return retry.Default()
}
