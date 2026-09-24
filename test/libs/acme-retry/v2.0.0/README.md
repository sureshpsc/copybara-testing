# acme/retry v2.0.0

A small demo library. Breaking changes from v1:

| v1 | v2 |
| --- | --- |
| `import "github.com/acme/retry"` | `import "github.com/acme/retry/v2"` |
| `Config.MaxTries` | `Config.MaxAttempts` |
| `retry.DefaultConfig()` | `retry.Default()` |
| `retry.Do(ctx, cfg, func(ctx context.Context) error {...})` | `retry.Do(ctx, cfg, func(ctx context.Context, attempt int) error {...})` |

New in v2: `retry.Permanent(err)` stops retrying at once.
