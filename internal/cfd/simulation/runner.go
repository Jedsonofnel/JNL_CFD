package simulation

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/profiler"
)

var prof = profiler.NewProfiler()

func RunFrame(scenario Scenario, dt float32, tracerFieldIndex int) []float32 {
	scenario.AdvanceTime(dt)

	converged := false
	for !converged {
		converged = scenario.Step(prof)
	}

	prof.PrintStatsEvery10Seconds(dt)

	return scenario.GetScalarPrognosticValues(tracerFieldIndex)
}
