package orders

import (
	"context"
	"errors"
	"testing"
)

func TestSubmitRetriesUntilSuccess(t *testing.T) {
	calls := 0
	err := Submit(context.Background(), func(context.Context) error {
		calls++
		if calls < 4 {
			return errors.New("busy")
		}
		return nil
	})
	if err != nil || calls != 4 {
		t.Fatalf("err=%v calls=%d", err, calls)
	}
}

func TestCancelGivesUpAfterTwo(t *testing.T) {
	calls := 0
	err := Cancel(context.Background(), func(context.Context) error {
		calls++
		return errors.New("down")
	})
	if err == nil || calls != 2 {
		t.Fatalf("err=%v calls=%d", err, calls)
	}
}
