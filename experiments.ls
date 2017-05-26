$ = require 'jquery'
P = require 'bluebird'
seqr = require './seqr.ls'
{runScenario, newEnv} = require './scenarioRunner.ls'
scenario = require './scenario.ls'
sounds = require './sounds.ls'

L = (s) -> s

runUntilPassed = seqr.bind (scenarioLoader, {passes=2, maxRetries=5}={}) ->*
	currentPasses = Number(localStorage.getItem("passes")) ? 0
	currRetry = Number(localStorage.getItem("retries")) ? 1
	console.log currentPasses, currRetry
	for retry from currRetry til Infinity
		task = runScenario scenarioLoader
		result = yield task.get \done

		currentPasses += result.passed

		localStorage.setItem('passes', Number(currentPasses))
		doQuit = currentPasses >= passes or retry > maxRetries
		localStorage.setItem('retries', Number(retry) + 1)
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
	yield runUntilPassed  scenario.closeTheGap, passes: 3

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
	line = 0.0
	name = scn.scenarioName
	if  name == 'switchLanes' || name == 'laneDriving'
		line = 3.6
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
					overedge = Math.max (wheel.position.x - line), overedge
					overedge = Math.max ((-3.6) - wheel.position.x), overedge
				if not overedge? or not isFinite overedge
					return
				if overedge < -0.3 or scene.endtime
					warningSound.stop()
				else
					warningSound.start()
				return if overedge < 1.0
				title = env.L "Oops!"
				reason = env.L "You drove out of your lane."
				if line == 3.6
					reason = env.L "You drove out of the road."
				scenario.endingVr scene, env, title, reason, task

			scene.onExit ->
				warningSound.stop()
		return task

export vrIntro = seqr.bind ->*

	env = newEnv!
	yield scenario.participantInformation yield env.get \env
	env.let \destroy
	yield env
	
	monkeyPatch = laneChecker

	yield runUntilPassed monkeyPatch scenario.closeTheGap
	yield runUntilPassed monkeyPatch scenario.switchLanes
	yield runUntilPassed monkeyPatch scenario.speedControl

	if localStorage.hasOwnProperty('experiment') == false || localStorage.getItem("scenario_id") == nTrials
		localStorage.setItem('scenario_id', 0)
		experiment = []
			.concat([0]*2)
			.concat([1]*2)
			.concat([2]*2)
		experiment = shuffleArray experiment
		localStorage.setItem('experiment', JSON.stringify(experiment))

export vrExperiment = seqr.bind ->*
	scenarios = [scenario.closeTheGap, scenario.switchLanes, scenario.speedControl, scenario.laneDriving, scenario.followInTraffic, scenario.blindFollowInTraffic, scenario.calibration, scenario.verification]
	nTrials = 12
	lanechecker = laneChecker
	pass_times = [1, 1, 2,2,2,1,1,1,1,1,1]

	if localStorage.hasOwnProperty('experiment') == false || localStorage.getItem("scenario_id") == nTrials

		experiment = []
			.concat([3]*2)
			.concat([4]*2)
			.concat([5]*2)

		experiment = shuffleArray experiment
		experiment.push 5, 4, 3, 2, 1, 0, 7, 6
		experiment.reverse()

		env = newEnv!
		yield scenario.experimentIntro yield env.get \env
		env.let \destroy
		yield env

		localStorage.setItem('scenario_id', 0)
		localStorage.setItem('experiment', JSON.stringify(experiment))
		localStorage.setItem('passes', 0)
		localStorage.setItem('retries', 1)
		window.location.reload()
	else
		experiment = JSON.parse(localStorage.getItem("experiment"))
		id = localStorage.getItem("scenario_id")
		console.log id
		if id <= 5
			yield runUntilPassed lanechecker(scenarios[experiment[id]]), passes: pass_times[id]
		else
			yield runUntilPassed lanechecker(scenarios[experiment[id]]), passes: 1, maxRetries: 2
		localStorage.setItem('passes', 0)
		localStorage.setItem('scenario_id', Number(id) + 1)
		localStorage.setItem('retries', 1)
		window.location.reload()

	if localStorage.getItem("scenario_id") == nTrials
		env = newEnv!
		yield scenario.experimentOutro yield env.get \env
		env.let \destroy
		yield env


export forwarder = seqr.bind ->*
	if localStorage.hasOwnProperty('scenario_id')
		id = localStorage.getItem("scenario_id")
		localStorage.setItem('scenario_id', Number(id) + 1)

export backwarder = seqr.bind ->*
	if localStorage.hasOwnProperty('scenario_id')
		id = localStorage.getItem("scenario_id")
		localStorage.setItem('scenario_id', Number(id) - 1)


export resetter = seqr.bind ->*
	if localStorage.hasOwnProperty('experiment')
		exp = localStorage.getItem("experiment")
		pas = localStorage.getItem('passes')
		ret = localStorage.getItem('retries')
		id = localStorage.getItem('scenario_id')

		localStorage.setItem('experiment_copy', exp)
		localStorage.setItem('passes_copy', pas)
		localStorage.setItem('retries_copy', ret)
		localStorage.setItem('scenario_id_copy', id)

		localStorage.removeItem("experiment")
		localStorage.removeItem('passes')
		localStorage.removeItem('retries')
		localStorage.removeItem('scenario_id')

	env = newEnv!
	yield scenario.resetterOutro yield env.get \env
	env.let \destroy
	yield env

export backupper = seqr.bind ->*
	if localStorage.hasOwnProperty('experiment') == false && localStorage.hasOwnProperty('experiment_copy')
		exp = localStorage.getItem("experiment_copy")
		pas = localStorage.getItem('passes_copy')
		ret = localStorage.getItem('retries_copy')
		id = localStorage.getItem('scenario_id_copy')

		localStorage.setItem('experiment', exp)
		localStorage.setItem('passes', pas)
		localStorage.setItem('retries', ret)
		localStorage.setItem('scenario_id', id)

	env = newEnv!
	yield scenario.reResetterOutro yield env.get \env
	env.let \destroy
	yield env
	

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
	monkeypatch = laneChecker
	yield runScenario monkeypatch scn


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

