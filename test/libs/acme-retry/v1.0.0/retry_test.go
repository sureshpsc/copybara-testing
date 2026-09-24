package retry

import (
	"context"
	"errors"
	"testing"
)

func TestDoStopsOnSuccess(t *testing.T) {
	calls := 0
	err := Do(context.Background(), Config{MaxTries: 5}, func(context.Context) error {
		calls++
		if calls < 3 {
			return errors.New("busy")
		}
		return nil
	})
	if err != nil || calls != 3 {
		t.Fatalf("err=%v calls=%d", err, calls)
	}
}

func TestDoReturnsLastError(t *testing.T) {
	calls := 0
	err := Do(context.Background(), Config{MaxTries: 2}, func(context.Context) error {
		calls++
		return errors.New("down")
	})
	if err == nil || calls != 2 {
		t.Fatalf("err=%v calls=%d", err, calls)
	}
}
