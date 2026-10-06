package core

// PreparedIntentSlot owns the result of choosing a target before Fuwa takes
// focus. An unsuccessful selection is a prepared result too: consuming it must
// not fall through to a different window behind a system dialog.
//
// The caller scopes the slot to the management UI lifecycle, clearing it on
// hide, deactivation, privacy teardown, or an explicit target selection. Consume
// clears it before returning so permission requests and repeated clicks cannot
// reuse the previous target.
type PreparedIntentSlot struct {
	window   Window
	err      error
	prepared bool
}

func (s *PreparedIntentSlot) Replace(w Window, err error) {
	s.window, s.err, s.prepared = w, err, true
}

func (s *PreparedIntentSlot) Consume() (Window, error, bool) {
	w, err, prepared := s.window, s.err, s.prepared
	s.Clear()
	return w, err, prepared
}

func (s *PreparedIntentSlot) Clear() {
	*s = PreparedIntentSlot{}
}
