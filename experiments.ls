$ = require 'jquery'
P = require 'bluebird'
seqr = require './seqr.ls'
{runScenario, newEnv} = require './scenarioRunner.ls'
scenario = require './scenario.ls'
sounds = require './sounds.ls'

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

	intervals = shuffleArray [1, 1, 2, 2, 3, 3]
	for interval in intervals
		yield runScenario scenario.forcedBlindFollowInTraffic, interval: interval

	env = newEnv!
	yield scenario.experimentOutro yield env.get \env
	env.let \destroy
	yield env


# Down the rabbit hole with hacks...
wrapScenario = (f) -> (scenario) ->
	wrapper = f(scenario)
	if not wrapper.scenarioName?
		wrapper.scenarioName = scenario.scenarioName
	return wrapper

laneChecker = wrapScenario (scn) ->
	(env, ...args) ->
		env.opts.forceSteering = true
		env.opts.steeringNoise = true
		task = scn env, ...args

		task.get(\scene).then seqr.bind (scene) !->*
			return if not scene.player
			warningSound = yield sounds.WarningSound env
			lanecenter = scene.player.physical.position.x
			# This is rather horrible!
			scene.afterPhysics (dt) !->
				overedge = -10
				for wheel in scene.player.wheels
					overedge = Math.max (wheel.position.x - 0.0), overedge
					overedge = Math.max ((-7/2.0) - wheel.position.x), overedge
				if not overedge? or not isFinite overedge
					return
				if overedge < -0.3 or scene.endtime
					warningSound.stop()
				else
					warningSound.start()
				return if overedge < 0.2
				title = env.L "Oops!"
				reason = env.L "You drove out of your lane."
				scenario.endingVr scene, env, title, reason, task

			scene.onExit ->
				warningSound.stop()
		return task

export vrPractice = seqr.bind ->*
	#yield runUntilPassed scenario.closeTheGap
	#yield runUntilPassed scenario.switchLanes
	yield runUntilPassed scenario.speedControl

export vrExperiment = seqr.bind ->*
	yield runUntilPassed scenario.laneDriving, passes: 3

export vrBlindFollow = seqr.bind ->*
	monkeypatch = laneChecker
	yield runUntilPassed laneChecker scenario.followInTraffic
	yield runUntilPassed scenario.blindFollowInTraffic

export vrExperiment = seqr.bind ->*

	#env = newEnv!
	#yield scenario.participantInformation yield env.get \env
	#env.let \destroy
	#yield env

	#yield runScenario scenario.calibration
	#yield runScenario scenario.verification

	yield runUntilPassed scenario.laneDriving, passes: 3

	yield runUntilPassed scenario.followInTraffic
	yield runUntilPassed scenario.blindFollowInTraffic

export blindFollow17 = seqr.bind ->*
	monkeypatch = laneChecker

	env = newEnv!
	yield scenario.participantInformation yield env.get \env
	env.let \destroy
	yield env

	#yield runScenario scenario.runTheLight
	yield runUntilPassed monkeypatch scenario.closeTheGap, passes: 3

	yield runUntilPassed monkeypatch scenario.stayOnLane
	yield runUntilPassed monkeypatch scenario.speedControl
	yield runUntilPassed monkeypatch scenario.blindSpeedControl

	yield runUntilPassed monkeypatch scenario.followInTraffic
	yield runUntilPassed monkeypatch scenario.blindFollowInTraffic

	monkeypatch = wrapScenario (scenario) ->
		scenario = laneChecker scenario
		(env, ...args) ->
			env.notifications.hide()
			return scenario env, ...args

	ntrials = 4
	scenarios = []
		.concat([scenario.followInTraffic]*ntrials)
		.concat([scenario.blindFollowInTraffic]*ntrials)
	scenarios = shuffleArray scenarios

	for scn in scenarios
		yield runScenario monkeypatch scn

	intervals = shuffleArray [1, 1, 2, 2, 3, 3]
	for interval in intervals
		yield runScenario monkeypatch scenario.forcedBlindFollowInTraffic, interval: interval

	env = newEnv!
	yield scenario.experimentOutro yield env.get \env
	env.let \destroy
	yield env

export defaultExperiment = mulsimco2015

export freeDriving = seqr.bind ->*
	yield runScenario scenario.freeDriving

runWithNewEnv = seqr.bind (scenario, ...args) ->*
	envP = newEnv!
	env = yield envP.get \env
	ret = yield scenario env, ...args
	envP.let \destroy
	yield envP
	return ret

export blindPursuit = seqr.bind ->*
	yield runWithNewEnv scenario.participantInformationBlindPursuit
	totalScore =
		correct: 0
		incorrect: 0
	yield runWithNewEnv scenario.soundSpook, preIntro: true

	runPursuitScenario = seqr.bind (...args) ->*
		task = runScenario ...args
		env = yield task.get \env
		res = yield task.get \done

		totalScore.correct += res.result.score.correct
		totalScore.incorrect += res.result.score.incorrect
		totalPercentage = totalScore.correct/(totalScore.correct + totalScore.incorrect)*100
		res.outro \content .append $ env.L "%blindPursuit.totalScore", score: totalPercentage
		yield task
		return res
	res = yield runPursuitScenario scenario.pursuitDiscriminationPractice
	frequency = res.result.estimatedFrequency
	nBlocks = 2
	trialsPerBlock = 2
	for block from 0 til nBlocks
		for trial from 0 til trialsPerBlock
			yield runPursuitScenario scenario.pursuitDiscrimination, frequency: frequency
		yield runWithNewEnv scenario.soundSpook

	env = newEnv!
	yield scenario.experimentOutro (yield env.get \env), (env) ->
		totalPercentage = totalScore.correct/(totalScore.correct + totalScore.incorrect)*100
		@ \content .append env.L '%blindPursuit.finalScore', score: totalPercentage
	env.let \destroy
	yield env

deparam = require 'jquery-deparam'
export singleScenario = seqr.bind ->*
	# TODO: The control flow is a mess!
	opts = deparam window.location.search.substring 1
	scn = scenario[opts.singleScenario]
	yield runScenario scn


export calibration = seqr.bind ->*
	yield runScenario scenario.calibration
	yield runScenario scenario.verification


export memkiller = seqr.bind !->*
	#loader = scenario.minimalScenario
	loader = scenario.blindFollowInTraffic
	#loader = scenario.freeDriving
	#for i from 1 to 1
	#	console.log i
	#	scn = loader()
	#	yield scn.get \scene
	#	scn.let \run
	#	scn.let \done
	#	yield scn
	#	void

	for i from 1 to 1
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

		console.log "Memory usage: ", window?performance?memory?totalJSHeapSize/1024/1024
		if window.gc
			for i from 0 til 10
				window.gc()
			console.log "Memory usage (after gc): ", window?performance?memory?totalJSHeapSize/1024/1024
	return i

export scenehanger = seqr.bind !->*
	#monkeypatch = laneChecker
	monkeypatch = wrapScenario (scenario) ->
		#scenario = laneChecker scenario
		(env, ...args) ->
			task = scenario env, ...args
			task.get(\run).then seqr.bind !->*
				scene = yield task.get \scene
				scene.beforePhysics ->
					env.controls.throttle = 1.0
			return task

	for i from 0 to 100
		runner = runScenario monkeypatch scenario.stayOnLane
		[scn] = yield runner.get 'ready'
		[intro] = yield runner.get 'intro'
		if intro.let
			intro.let \accept
		[outro] = yield runner.get 'outro'
		outro.let \accept
		yield runner
		console.log "Task done"

export logkiller = seqr.bind !->*
	scope = newEnv!
	env = yield scope.get \env
	for i from 0 to 1000
		env.logger.write foo: "bar"

	scope.let \destroy
	yield scope
	console.log "Done"

