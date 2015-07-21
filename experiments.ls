$ = require 'jquery'

seqr = require './seqr.ls'
{runScenario, newEnv} = require './scenarioRunner.ls'
scenario = require './scenario.ls'

L = (s) -> s

export mulsimco2015 = seqr.bind ->*
	env = newEnv!
	yield scenario.participantInformation yield env.get \env
	env.let \destroy
	yield env
	yield runScenario scenario.runTheLight

	passesWanted = 2
	maxRetries = 5

	passes = 0
	for retry from 1 til Infinity
		task = runScenario scenario.throttleAndBrake
		result = yield task.get \done
		passes += result.passed

		doRetry = not (passes >= passesWanted and retry < maxRetries)
		if doRetry
			result.outro \content .append $ L "<p>Let's try that again.</p>"
		yield task
		if not doRetry
			break

	passes = 0
	for retry from 1 til Infinity
		task = runScenario scenario.speedControl
		result = yield task.get \done
		passes += result.passed

		doRetry = not (passes >= passesWanted and retry < maxRetries)
		if doRetry
			result.outro \content .append $ L "<p>Let's try that again.</p>"
		yield task
		if not doRetry
			break

export defaultExperiment = mulsimco2015

export freeDriving = seqr.bind ->*
	yield runScenario scenario.freeDriving

deparam = require 'jquery-deparam'
export singleScenario = seqr.bind ->*
	# TODO: The control flow is a mess!
	opts = deparam window.location.search.substring 1
	scn = scenario[opts.singleScenario]
	while true
		yield runScenario scn
