$ = require 'jquery'
P = require 'bluebird'
seqr = require './seqr.ls'
{runScenario, runScenarioCurve, newEnv} = require './scenarioRunner.ls'
scenario = require './scenario.ls'

L = (s) -> s

runUntilPassed = seqr.bind (scenarioLoader, {passes=2, maxRetries=5}={}) ->*
	currentPasses = 0
	for retry from 1 til Infinity
		task = runScenario scenarioLoader
		result = yield task.get \done
		currentPasses += result.passed

		doQuit = currentPasses >= passes or retry > maxRetries
		#if not doQuit
		#	result.outro \content .append $ L "<p>Let's try that again.</p>"
		yield task
		if doQuit
			break

shuffleArray = (a) ->
	i = a.length
	while (--i) > 0
		j = Math.floor (Math.random()*(i+1))
		[a[i], a[j]] = [a[j], a[i]]
	return a


export mulsimco2015 = seqr.bind ->*
	env = newEnv!
	yield scenario.participantInformation yield env.get \env
	env.let \destroy
	yield env

	#yield runScenario scenario.runTheLight
	yield runUntilPassed scenario.closeTheGap, passes: 3

	yield runUntilPassed scenario.throttleAndBrake
	yield runUntilPassed scenario.speedControl
	yield runUntilPassed scenario.blindSpeedControl

	yield runUntilPassed scenario.followInTraffic
	yield runUntilPassed scenario.blindFollowInTraffic

	ntrials = 4
	scenarios = []
		.concat([scenario.followInTraffic]*ntrials)
		.concat([scenario.blindFollowInTraffic]*ntrials)
	scenarios = shuffleArray scenarios

	for scn in scenarios
		yield runScenario scn
	#trials = 6


export defaultExperiment = mulsimco2015

export freeDriving = seqr.bind ->*
	yield runScenario scenario.freeDriving

deparam = require 'jquery-deparam'
export singleScenario = seqr.bind ->*
	# TODO: The control flow is a mess!
	opts = deparam window.location.search.substring 1
	scn = scenario[opts.singleScenario]
	scnName = opts.singleScenario
	while true
		if scnName == "circleDriving" || scnName == "circleDrivingRev"
			yield runScenarioCurve scn
		else
			yield runScenario scn


export memkiller = seqr.bind !->*
	#loader = scenario.minimalScenario
	loader = scenario.blindFollowInTraffic
	#for i from 1 to 1
	#	console.log i
	#	scn = loader()
	#	yield scn.get \scene
	#	scn.let \run
	#	scn.let \done
	#	yield scn
	#	void

	for i from 1 to 10
		console.log i
		yield do seqr.bind !->*
			runner = runScenario loader
			[scn] = yield runner.get 'ready'
			console.log "Got scenario"
			[intro] = yield runner.get 'intro'
			if intro.let
				intro.let \accept
			yield P.delay 1000
			scn.let 'done', passed: false, outro: title: "Yay"
			runner.let 'done'
			[outro] = yield runner.get 'outro'
			outro.let \accept
			console.log "Running"
			yield runner
			console.log "Done"

		console.log "Memory usage: ", window.performance.memory.totalJSHeapSize/1024/1024
		if window.gc
			for i from 0 til 10
				window.gc()
			console.log "Memory usage (after gc): ", window.performance.memory.totalJSHeapSize/1024/1024
	return i

export logkiller = seqr.bind !->*
	scope = newEnv!
	env = yield scope.get \env
	for i from 0 to 1000
		env.logger.write foo: "bar"

	scope.let \destroy
	yield scope
	console.log "Done"


runUntilPassedCircle = seqr.bind (scenarioLoader, {passes=2, maxRetries=5}={}, rx, ry, l, s, rev, stat, four, fut) ->*
	currentPasses = 0
	for retry from 1 til Infinity
		task = runScenarioCurve scenarioLoader, rx, ry, l, s, rev, stat, four, fut
		result = yield task.get \done
		currentPasses += result.passed
		doQuit = currentPasses >= passes or retry > maxRetries
		#if not doQuit
		#	result.outro \content .append $ L "<p>Let's try that again.</p>"
		yield task
		if doQuit
			break

export circleDriving = seqr.bind ->*
	env = newEnv!
	yield scenario.participantInformation yield env.get \env
	env.let \destroy
	yield env

	yield runUntilPassedCircle scenario.circleDriving, passes: 1, maxRetries: 1
	yield runUntilPassedCircle scenario.circleDriving, passes: 1, maxRetries: 1, 200, 200, 50, 80, 1, false, true, 0
	yield runUntilPassedCircle scenario.circleDriving, passes: 1, maxRetries: 1, 200, 200, 50, 80, 1, false, true, 3
	yield runUntilPassedCircle scenario.circleDriving, passes: 1, maxRetries: 1, 200, 200, 50, 80, 1, false, true, 2

	yield runUntilPassedCircle scenario.circleDrivingRev, passes: 1, maxRetries: 1, 200, 200, 50, 80, -1, true, 1
	yield runUntilPassedCircle scenario.circleDrivingRev, passes: 1, maxRetries: 1, 200, 200, 50, 80, -1, true, 0
	yield runUntilPassedCircle scenario.circleDrivingRev, passes: 1, maxRetries: 1, 200, 200, 50, 80, -1, true, 3
	yield runUntilPassedCircle scenario.circleDrivingRev, passes: 1, maxRetries: 1, 200, 200, 50, 80, -1, true, 2



