package core

import (
	"errors"
	"testing"
)

func TestFailedCaptureRetryRejectsPreviousGeneration(t *testing.T) {
	w := sample(1, 2)
	s := NewSession(3, w)
	s.Fail(s.Generation, "first_frame_timeout")
	s.Missing = 1
	if err := s.Retry(w); err != nil {
		t.Fatal(err)
	}
	if s.Token != 3 || s.State != Starting || s.Generation != 2 || s.Error != "" || s.Missing != 0 || s.HasFrame {
		t.Fatal("retry did not prepare an independent attempt", s)
	}
	if s.ReceiveFrame(1) || s.Fail(1, "late_failure") {
		t.Fatal("previous attempt changed retry state")
	}
	if !s.ReceiveFrame(2) || s.State != Live {
		t.Fatal("retry could not become live", s)
	}
}

func TestRetryCannotSubstituteOrResurrectSource(t *testing.T) {
	w := sample(1, 2)
	for _, tc := range []struct {
		name   string
		state  State
		closed bool
		target Window
		want   error
	}{
		{"closed source", Failed, true, w, ErrClosed},
		{"different window", Failed, false, sample(2, 2), ErrClosed},
		{"reused owner pid", Failed, false, Window{ID: w.ID, PID: w.PID, Birth: w.Birth + 1}, ErrClosed},
		{"already live", Live, false, w, ErrTransition},
		{"already starting", Starting, false, w, ErrTransition},
		{"stopped", Stopped, false, w, ErrTransition},
		{"frozen uses resume", Frozen, false, w, ErrTransition},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := NewSession(3, w)
			s.State, s.Closed, s.Error = tc.state, tc.closed, "capture_start_failed"
			before := s
			if err := s.Retry(tc.target); !errors.Is(err, tc.want) {
				t.Fatal("incorrect retry result", err)
			}
			if s != before {
				t.Fatal("rejected retry mutated the existing pin", before, s)
			}
		})
	}
}
