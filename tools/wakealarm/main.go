package main

import (
	_ "embed"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	_ "time/tzdata"
)

type config struct {
	times      string
	timezone   string
	hold       time.Duration
	onceAfter  time.Duration
	once       bool
	wakeLock   string
	wakeUnlock string
	tag        string
	statusFile string
	logFile    string
}

func main() {
	configuration := parseFlags()
	logger, closeLog, err := newLogger(configuration.logFile)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer closeLog()

	location, err := time.LoadLocation(configuration.timezone)
	if err != nil {
		logger.Fatalf("invalid timezone %q: %v", configuration.timezone, err)
	}
	time.Local = location
	times, err := parseClockTimes(configuration.times)
	if err != nil {
		logger.Fatal(err)
	}

	interrupts := make(chan os.Signal, 1)
	signal.Notify(interrupts, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(interrupts)

	for {
		now := time.Now()
		when := nextScheduledTime(now, times, location)
		if configuration.onceAfter > 0 {
			when = now.Add(configuration.onceAfter)
		}
		writeStatus(configuration.statusFile, "waiting", when, time.Time{})
		logger.Printf("next wake: %s", when.In(location).Format(time.RFC3339))

		alarmDone := make(chan error, 1)
		go func() { alarmDone <- waitForAlarm(when) }()
		select {
		case signalValue := <-interrupts:
			logger.Printf("stopped by %s", signalValue)
			writeStatus(configuration.statusFile, "stopped", time.Time{}, time.Time{})
			return
		case err := <-alarmDone:
			if err != nil {
				logger.Fatalf("alarm failed: %v", err)
			}
		}

		releaseAt := time.Now().Add(configuration.hold)
		if err := setWakeLock(configuration.wakeLock, configuration.tag); err != nil {
			logger.Printf("wake lock failed: %v", err)
			writeStatus(configuration.statusFile, "error", when, time.Time{})
			if configuration.once {
				return
			}
			continue
		}
		writeStatus(configuration.statusFile, "holding", when, releaseAt)
		logger.Printf("wake lock acquired until %s", releaseAt.In(location).Format(time.RFC3339))

		timer := time.NewTimer(configuration.hold)
		select {
		case signalValue := <-interrupts:
			if !timer.Stop() {
				<-timer.C
			}
			releaseWakeLock(configuration.wakeUnlock, configuration.tag)
			logger.Printf("stopped by %s", signalValue)
			writeStatus(configuration.statusFile, "stopped", time.Time{}, time.Time{})
			return
		case <-timer.C:
			releaseWakeLock(configuration.wakeUnlock, configuration.tag)
			logger.Printf("wake lock released")
		}
		if configuration.once {
			writeStatus(configuration.statusFile, "completed", when, releaseAt)
			return
		}
	}
}

func parseFlags() config {
	configuration := config{}
	var holdSeconds int
	var onceAfterSeconds int
	flag.StringVar(&configuration.times, "times", "09:57,17:57", "comma-separated local wake times")
	flag.StringVar(&configuration.timezone, "timezone", "Asia/Shanghai", "IANA timezone")
	flag.IntVar(&holdSeconds, "hold", 300, "seconds to hold the kernel wake lock")
	flag.IntVar(&onceAfterSeconds, "once-after", 0, "test mode: wake after this many seconds")
	flag.BoolVar(&configuration.once, "once", false, "exit after one wake cycle")
	flag.StringVar(&configuration.wakeLock, "wake-lock", "/sys/power/wake_lock", "wake_lock sysfs path")
	flag.StringVar(&configuration.wakeUnlock, "wake-unlock", "/sys/power/wake_unlock", "wake_unlock sysfs path")
	flag.StringVar(&configuration.tag, "tag", "dockroot_scheduled_wake", "kernel wake-lock tag")
	flag.StringVar(&configuration.statusFile, "status-file", "", "status output file")
	flag.StringVar(&configuration.logFile, "log-file", "", "append-only log file")
	flag.Parse()
	if holdSeconds < 1 || holdSeconds > 3600 {
		fmt.Fprintln(os.Stderr, "hold must be between 1 and 3600 seconds")
		os.Exit(2)
	}
	if onceAfterSeconds < 0 || onceAfterSeconds > 86400 {
		fmt.Fprintln(os.Stderr, "once-after must be between 0 and 86400 seconds")
		os.Exit(2)
	}
	configuration.hold = time.Duration(holdSeconds) * time.Second
	configuration.onceAfter = time.Duration(onceAfterSeconds) * time.Second
	return configuration
}

func newLogger(path string) (*log.Logger, func(), error) {
	if path == "" {
		return log.New(os.Stdout, "[wakealarm] ", log.LstdFlags), func() {}, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, nil, err
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return nil, nil, err
	}
	return log.New(file, "[wakealarm] ", log.LstdFlags), func() { _ = file.Close() }, nil
}

func setWakeLock(path, tag string) error {
	err := os.WriteFile(path, []byte(tag), 0)
	if err == nil {
		return nil
	}
	content, readErr := os.ReadFile(path)
	if readErr == nil && strings.Contains(string(content), tag) {
		return nil
	}
	return err
}

func releaseWakeLock(path, tag string) {
	_ = os.WriteFile(path, []byte(tag), 0)
}

func writeStatus(path, state string, next, release time.Time) {
	if path == "" {
		return
	}
	content := fmt.Sprintf("state=%s\n", state)
	if !next.IsZero() {
		content += fmt.Sprintf("next_epoch=%d\n", next.Unix())
	}
	if !release.IsZero() {
		content += fmt.Sprintf("release_epoch=%d\n", release.Unix())
	}
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, []byte(content), 0600); err == nil {
		_ = os.Rename(temporary, path)
	}
}
