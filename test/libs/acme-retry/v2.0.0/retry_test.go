package retry

import (
	"context"
	"errors"
	"testing"
)

func TestDoPassesAttempt(t *testing.T) {
	var seen []int
	err := Do(context.Background(), Config{MaxAttempts: 5}, func(_ context.Context, attempt int) error {
		seen = append(seen, attempt)
		if attempt < 3 {
			return errors.New("busy")
		}
		return nil
	})
	if err != nil || len(seen) != 3 || seen[2] != 3 {
		t.Fatalf("err=%v seen=%v", err, seen)
	}
}

func TestPermanentStops(t *testing.T) {
	calls := 0
	want := errors.New("bad request")
	err := Do(context.Background(), Config{MaxAttempts: 5}, func(context.Context, int) error {
		calls++
		return Permanent(want)
	})
	if !errors.Is(err, want) || calls != 1 {
		t.Fatalf("err=%v calls=%d", err, calls)
	}
}
