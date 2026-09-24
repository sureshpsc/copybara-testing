// Package speech calls a Google API through gax-go, the way generated Google clients do.
package speech

import (
	"context"
	"time"

	gax "github.com/googleapis/gax-go"
)

// Recognize calls do and retries it on the default codes.
func Recognize(ctx context.Context, do func(context.Context) error) error {
	return gax.Invoke(ctx, func(ctx context.Context) error {
		return do(ctx)
	}, gax.WithRetry(func() gax.Retryer {
		return gax.OnCodes(nil, gax.Backoff{Initial: time.Millisecond})
	}))
}
