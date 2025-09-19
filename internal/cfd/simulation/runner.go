package simulation

func RunFrame(scenario Scenario, dt float32, tracerFieldIndex int) []float32 {
	scenario.AdvanceTime(dt)

	converged := false
	for !converged {
		converged = scenario.Step()
	}

	return scenario.GetScalarPrognosticValues(tracerFieldIndex)
}
