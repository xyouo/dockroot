package main

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"
)

type clockTime struct {
	hour   int
	minute int
	second int
}

func parseClockTimes(value string) ([]clockTime, error) {
	parts := strings.Split(value, ",")
	times := make([]clockTime, 0, len(parts))
	for _, part := range parts {
		fields := strings.Split(strings.TrimSpace(part), ":")
		if len(fields) < 2 || len(fields) > 3 {
			return nil, fmt.Errorf("invalid wake time %q", part)
		}
		numbers := make([]int, len(fields))
		for index, field := range fields {
			number, err := strconv.Atoi(field)
			if err != nil {
				return nil, fmt.Errorf("invalid wake time %q", part)
			}
			numbers[index] = number
		}
		if numbers[0] > 23 || numbers[1] > 59 || (len(numbers) == 3 && numbers[2] > 59) {
			return nil, fmt.Errorf("invalid wake time %q", part)
		}
		entry := clockTime{hour: numbers[0], minute: numbers[1]}
		if len(numbers) == 3 {
			entry.second = numbers[2]
		}
		times = append(times, entry)
	}
	if len(times) == 0 {
		return nil, fmt.Errorf("no wake times configured")
	}
	sort.Slice(times, func(i, j int) bool {
		left := times[i].hour*3600 + times[i].minute*60 + times[i].second
		right := times[j].hour*3600 + times[j].minute*60 + times[j].second
		return left < right
	})
	return times, nil
}

func nextScheduledTime(now time.Time, times []clockTime, location *time.Location) time.Time {
	localNow := now.In(location)
	for dayOffset := 0; ; dayOffset++ {
		day := localNow.AddDate(0, 0, dayOffset)
		for _, entry := range times {
			candidate := time.Date(day.Year(), day.Month(), day.Day(), entry.hour, entry.minute, entry.second, 0, location)
			if candidate.After(localNow) {
				return candidate
			}
		}
	}
}
