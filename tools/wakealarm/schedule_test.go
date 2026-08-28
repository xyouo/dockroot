package main

import (
	"testing"
	"time"
)

func TestParseAndNextScheduledTime(t *testing.T) {
	times, err := parseClockTimes("17:57,09:57:30")
	if err != nil {
		t.Fatal(err)
	}
	location := time.FixedZone("CST", 8*60*60)
	now := time.Date(2026, 8, 28, 10, 0, 0, 0, location)
	got := nextScheduledTime(now, times, location)
	want := time.Date(2026, 8, 28, 17, 57, 0, 0, location)
	if !got.Equal(want) {
		t.Fatalf("next wake = %v, want %v", got, want)
	}

	now = time.Date(2026, 8, 28, 18, 0, 0, 0, location)
	got = nextScheduledTime(now, times, location)
	want = time.Date(2026, 8, 29, 9, 57, 30, 0, location)
	if !got.Equal(want) {
		t.Fatalf("next-day wake = %v, want %v", got, want)
	}
}

func TestRejectsInvalidWakeTime(t *testing.T) {
	for _, value := range []string{"", "9", "24:00", "09:60", "abc"} {
		if _, err := parseClockTimes(value); err == nil {
			t.Fatalf("expected %q to be rejected", value)
		}
	}
}
