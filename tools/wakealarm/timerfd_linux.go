//go:build linux

package main

import (
	"fmt"
	"syscall"
	"time"
	"unsafe"
)

const (
	clockRealtimeAlarm = 8
	tfdTimerAbsolute   = 1
)

type kernelTimespec struct {
	seconds     int64
	nanoseconds int64
}

type kernelItimerspec struct {
	interval kernelTimespec
	value    kernelTimespec
}

func waitForAlarm(when time.Time) error {
	fd, _, errno := syscall.Syscall(syscall.SYS_TIMERFD_CREATE, clockRealtimeAlarm, 0, 0)
	if errno != 0 {
		return fmt.Errorf("timerfd_create(CLOCK_REALTIME_ALARM): %w", errno)
	}
	defer syscall.Close(int(fd))

	spec := kernelItimerspec{value: kernelTimespec{seconds: when.Unix(), nanoseconds: int64(when.Nanosecond())}}
	_, _, errno = syscall.Syscall6(
		syscall.SYS_TIMERFD_SETTIME,
		fd,
		tfdTimerAbsolute,
		uintptr(unsafe.Pointer(&spec)),
		0,
		0,
		0,
	)
	if errno != 0 {
		return fmt.Errorf("timerfd_settime: %w", errno)
	}

	buffer := make([]byte, 8)
	for {
		_, err := syscall.Read(int(fd), buffer)
		if err == syscall.EINTR {
			continue
		}
		return err
	}
}
