//go:build !linux

package main

import "time"

func waitForAlarm(when time.Time) error {
	time.Sleep(time.Until(when))
	return nil
}
