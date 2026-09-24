package speech

import (
	"context"
	"errors"
	"testing"
)

func TestRecognizeCallsOnce(t *testing.T) {
	calls := 0
	err := Recognize(context.Background(), func(context.Context) error {
		calls++
		return nil
	})
	if err != nil || calls != 1 {
		t.Fatalf("err=%v calls=%d", err, calls)
	}
}

func TestRecognizeReturnsError(t *testing.T) {
	want := errors.New("unavailable")
	err := Recognize(context.Background(), func(context.Context) error { return want })
	if !errors.Is(err, want) {
		t.Fatalf("err=%v", err)
	}
}
