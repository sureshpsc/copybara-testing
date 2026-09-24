package orders

import (
	"context"

	"github.com/acme/retry/v2"
)

func submit(ctx context.Context, cfg retry.Config, send func(context.Context) error) error {
	return retry.Do(ctx, cfg, func(ctx context.Context) error {
		return send(ctx)
	})
}
