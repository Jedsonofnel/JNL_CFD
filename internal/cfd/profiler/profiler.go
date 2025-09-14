package profiler

import (
	"fmt"
	"strings"
	"sync"
	"time"
	"maps"
)

type Profiler interface {
	StartTimer(name string) func()
	GetStats() map[string]ProfileStats
	Reset()
	PrintStats()
}

type ProfileStats struct {
	TotalTime   time.Duration
	CallCount   int
	AverageTime time.Duration
	MaxTime     time.Duration
	MinTime     time.Duration
}

type CallStackProfiler struct {
	stack  []string
	timers map[string]time.Time
	stats  map[string]ProfileStats
	mu     sync.Mutex
}

func NewProfiler() Profiler {
	return &CallStackProfiler{
		stack:  make([]string, 0, 10), // Pre-allocate for typical depth
		timers: make(map[string]time.Time),
		stats:  make(map[string]ProfileStats),
	}
}

func (p *CallStackProfiler) StartTimer(name string) func() {
	p.mu.Lock()

	// Build hierarchical name
	fullName := name
	if len(p.stack) > 0 {
		fullName = strings.Join(p.stack, ".") + "." + name
	}

	// Push to stack and start timer
	p.stack = append(p.stack, name)
	startTime := time.Now()
	p.timers[fullName] = startTime

	p.mu.Unlock()

	// Return cleanup function
	return func() {
		p.mu.Lock()
		defer p.mu.Unlock()

		elapsed := time.Since(startTime)
		p.updateStats(fullName, elapsed)

		// Pop from stack
		if len(p.stack) > 0 {
			p.stack = p.stack[:len(p.stack)-1]
		}
		delete(p.timers, fullName)
	}
}

func (p *CallStackProfiler) updateStats(name string, elapsed time.Duration) {
	stats, exists := p.stats[name]
	if !exists {
		stats = ProfileStats{
			MinTime: elapsed,
			MaxTime: elapsed,
		}
	}

	stats.TotalTime += elapsed
	stats.CallCount++
	stats.AverageTime = stats.TotalTime / time.Duration(stats.CallCount)

	if elapsed < stats.MinTime {
		stats.MinTime = elapsed
	}
	if elapsed > stats.MaxTime {
		stats.MaxTime = elapsed
	}

	p.stats[name] = stats
}

func (p *CallStackProfiler) GetStats() map[string]ProfileStats {
	p.mu.Lock()
	defer p.mu.Unlock()
	return maps.Clone(p.stats)
}

func (p *CallStackProfiler) Reset() {
	p.mu.Lock()
	defer p.mu.Unlock()

	// Clear all data but keep allocated maps
	for k := range p.stats {
		delete(p.stats, k)
	}
	for k := range p.timers {
		delete(p.timers, k)
	}
	p.stack = p.stack[:0]
}

func (p *CallStackProfiler) PrintStats() {
	stats := p.GetStats()
	if len(stats) == 0 {
		fmt.Println("No profiling data available")
		return
	}

	fmt.Println("=== Profiling Stats ===")
	for name, stat := range stats {
		avgMs := float64(stat.AverageTime.Nanoseconds()) / 1e6
		totalMs := float64(stat.TotalTime.Nanoseconds()) / 1e6
		minMs := float64(stat.MinTime.Nanoseconds()) / 1e6
		maxMs := float64(stat.MaxTime.Nanoseconds()) / 1e6

		fmt.Printf("%s: avg=%.2fms total=%.2fms calls=%d min=%.2fms max=%.2fms\n",
			name, avgMs, totalMs, stat.CallCount, minMs, maxMs)
	}
}
