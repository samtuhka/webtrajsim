$ = require 'jquery'
P = require 'bluebird'
seqr = require './seqr.ls'
{runScenario, runScenarioCurve, newEnv} = require './scenarioRunner.ls'
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

laneChecker = wrapScenario (scenario) ->
	(env, ...args) ->
		env.opts.forceSteering = true
		env.opts.steeringNoise = true
		task = scenario env, ...args

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
				if overedge < -0.3
					warningSound.stop()
				else
					warningSound.start()
				return if overedge < 0.2
				task.let \done, passed: false, outro:
					title: env.L "Oops!"
					content: env.L "You drove out of your lane."
			scene.onExit ->
				warningSound.stop()
		return task

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
	scnName = opts.singleScenario
	while true
		if scnName == "circleDriving" || scnName == "circleDrivingRev"
			yield runScenario scn
		else
			yield runScenario scn


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


runUntilPassedCircle = seqr.bind (scenarioLoader, {passes=2, maxRetries=5}={}, rx, ry, l, s, rev, stat, four, fut, inst) ->*
	currentPasses = 0
	for retry from 1 til Infinity
		task = runScenarioCurve scenarioLoader, rx, ry, l, s, rev, stat, four, fut, inst
		result = yield task.get \done
		currentPasses += result.passed
		doQuit = currentPasses >= passes or retry > maxRetries
		#if not doQuit
		#	result.outro \content .append $ L "<p>Let's try that again.</p>"
		yield task
		if doQuit
			break

export freeDrivingCurve = seqr.bind ->*
	s = 80
	rx = ((s/3.6)*22 / Math.PI)
	ry = rx
	l = (s/3.6)*8
	for i from 0 til 10
		if i%2 == 0
			yield runScenario scenario.circleDrivingFree, rx, ry, l, s, 1, false, false, 2, false, 0
		else
			yield runScenario scenario.circleDrivingRevFree, rx, ry, l, s, 1, false, false, 2, false, 0

runWithNewEnv = seqr.bind (scenario, i) ->*
	envP = newEnv!
	env = yield envP.get \env
	ret = yield scenario env, i
	envP.let \destroy
	yield envP
	return ret

deparam = require 'jquery-deparam'
opts = deparam window.location.search.substring 1
alt = Math.floor(opts.alt)

shuffle = (array) ->
	while true
		array = shuffleArray array
		quit = true
		for i from 1 til array.length
			if array[i][0] == array[i - 1][0]
				quit = false
		break if quit
	return array

export fixSwitch = seqr.bind ->*
	
	if localStorage.hasOwnProperty('experiment') == false
		pracScens = [[0,1],[1,1],[1,-1]]
		pracScens = shuffleArray pracScens
		
		experiment = [[2,1],[2,-1],[3, 1], [3, -1], [4, 1], [4, -1], [5, 1], [5, -1],[6, 1],[6, -1]]

		experiment = shuffle experiment
			
		experiment = experiment.concat pracScens
		experiment.reverse()

		yield runWithNewEnv scenario.participantInformation
		yield runWithNewEnv scenario.calibrationInst, 1
		yield runWithNewEnv scenario.calibrationInst, 3
	
		localStorage.setItem('scenario_id', 0)
		localStorage.setItem('experiment', JSON.stringify(experiment))
		localStorage.setItem('passes', 0)
		localStorage.setItem('retries', 1)
		window.location.reload()
	else
		experiment = JSON.parse(localStorage.getItem("experiment"))
		id = localStorage.getItem("scenario_id")
		if id < 1
			task = runScenario scenario.fixSwitch, hide: false, turn:experiment[id][1], allVisible:true, n:experiment[id][0], 
		else if id < 3
			task = runScenario scenario.fixSwitch, hide: true, turn:experiment[id][1], allVisible:true, n:experiment[id][0]
		else if id < 13
			task = runScenario scenario.fixSwitch, hide:true, turn:experiment[id][1], n:experiment[id][0],
		else
			yield runWithNewEnv scenario.calibrationInst, 1
			resetter()
			env = newEnv!
			yield scenario.experimentOutro yield env.get \env
			env.let \destroy
			yield env
			window.location.reload()

		result = yield task.get \done
		yield task

		#if id == 3 && result.passed
		#	yield runWithNewEnv scenario.calibrationInst, 1

		yield runWithNewEnv scenario.calibrationInst, 3

		if result.passed
			localStorage.setItem('passes', 0)
			localStorage.setItem('scenario_id', Number(id) + 1)
			localStorage.setItem('retries', 1)
		window.location.reload()


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

	#env = newEnv!
	#yield scenario.resetterOutro yield env.get \env
	#env.let \destroy
	#yield env

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

export circleDrivingTrue = seqr.bind ->*
	yield runWithNewEnv scenario.participantInformation

	dev = 0
	ntrials = 3
	rightParams = [2,2]
	leftParams = rightParams.slice()
	rightParams = shuffleArray rightParams
	leftParams = shuffleArray leftParams

	rightParamsDark = [2,2]
	leftParamsDark = rightParamsDark.slice()
	rightParamsDark = shuffleArray rightParamsDark
	leftParamsDark = shuffleArray leftParamsDark

	s = 80
	rx = ((s/3.6)*22 / Math.PI)
	ry = rx
	l = (s/3.6)*8
	i = 0
	j = 0
	k = 0
	h = 0
	v = 0.5

	scenarios = [scenario.circleDriving, scenario.circleDrivingRev, scenario.darkDriving, scenario.darkDrivingRev, scenario.circleDrivingRev, scenario.circleDriving, scenario.darkDrivingRev, scenario.darkDriving]
	if alt == 1
		scenarios.reverse()

	yield runWithNewEnv scenario.calibration, 1

	task = runScenarioCurve scenario.darkDriving, rx, ry, l, s, 1, false, false, 2 , "dark prac", dev, 0, v
	result = yield task.get \done
	result.outro \content .append $ L "<p>Seuraavaksi harjoitellaan kerran kokeen toista asetelmaa.</p>"
	result.outro \content .append $ L "<p>Kun olet valmis, paina ratin oikeaa punaista painiketta.</p>"
	yield task

	task = runScenarioCurve scenario.circleDriving, rx, ry, l, s, 1, false, false, 2 , "first", dev, 0, v
	result = yield task.get \done
	result.outro \content .append $ L "<p>Seuraavaksi kalibroidaan silmänliikekamera uudelleen, jonka jälkeen varsinainen koe alkaa.</p>"
	result.outro \content .append $ L "<p>Kun olet valmis, paina ratin oikeaa punaista painiketta.</p>"
	yield task

	yield runWithNewEnv scenario.calibration, 2

	for scn in scenarios
		if scn.scenarioName == "circleDriving"
			task = runScenarioCurve scn, rx, ry, l, s, 1, false, false, rightParams[i], "brief", dev, 0, v
			i += 1
		if scn.scenarioName == "circleDrivingRev"
			task = runScenarioCurve scn, rx, ry, l, s, 1, false, false, leftParams[j], "brief", dev, 0, v
			j += 1
		if scn.scenarioName == "darkDriving"
			task = runScenarioCurve scn, rx, ry, l, s, 1, false, false, rightParamsDark[k], "dark", dev, 0, v
			k += 1
		if scn.scenarioName == "darkDrivingRev"
			task = runScenarioCurve scn, rx, ry, l, s, 1, false, false, leftParamsDark[h], "dark", dev, 0, v
			h += 1
		result = yield task.get \done
		result.outro \content .append $ L "<p>Kun olet valmis, jatka koetta painamalla ratin oikeaa punaista painiketta.</p>"
		yield task

	yield runWithNewEnv scenario.calibration, 3

	yield runWithNewEnv scenario.experimentOutro


export circleDriving = seqr.bind ->*
	yield runWithNewEnv scenario.participantInformation

	dev = 0
	ntrials = 3
	rightParams = [2,2,2]
	leftParams = rightParams.slice()
	rightParams = shuffleArray rightParams
	leftParams = shuffleArray leftParams

	rightParamsDark = [2,2]
	leftParamsDark = rightParamsDark.slice()
	rightParamsDark = shuffleArray rightParamsDark
	leftParamsDark = shuffleArray leftParamsDark

	s = 80
	rx = ((s/3.6)*22 / Math.PI)
	ry = rx
	l = (s/3.6)*8
	i = 0
	j = 0
	k = 0
	h = 0
	v = 0.5

	scenarios = []
		.concat([scenario.circleDriving]*ntrials)
		.concat([scenario.circleDrivingRev]*ntrials)
		.concat([scenario.darkDriving]*2)
		.concat([scenario.darkDrivingRev]*2)
	scenarios = shuffleArray scenarios

	yield runWithNewEnv scenario.calibration, 1

	task = runScenarioCurve scenario.darkDriving, rx, ry, l, s, 1, false, false, 2 , "dark prac", dev, 0, v
	result = yield task.get \done
	result.outro \content .append $ L "<p>Kokeillaan samaa uudestaan.</p>"
	result.outro \content .append $ L "<p>Kun olet valmis, paina ratin oikeaa punaista painiketta.</p>"
	yield task

	task = runScenarioCurve scenario.darkDrivingRev, rx, ry, l, s, 1, false, false, 2, "dark still prac", dev, 0, v
	result = yield task.get \done
	result.outro \content .append $ L "<p>Seuraavaksi harjoitellaan kerran varsinaista koeasetelmaa.</p>"
	result.outro \content .append $ L "<p>Kun olet valmis, paina ratin oikeaa punaista painiketta.</p>"
	yield task

	task = runScenarioCurve scenario.circleDriving, rx, ry, l, s, 1, false, false, 2 , "first", dev, 0, v
	result = yield task.get \done
	result.outro \content .append $ L "<p>Seuraavaksi kalibroidaan silmänliikekamera uudelleen, jonka jälkeen varsinainen koe alkaa.</p>"
	result.outro \content .append $ L "<p>Kun olet valmis, paina ratin oikeaa punaista painiketta.</p>"
	yield task

	yield runWithNewEnv scenario.calibration, 2

	for scn in scenarios
		if scn.scenarioName == "circleDriving"
			task = runScenarioCurve scn, rx, ry, l, s, 1, false, false, rightParams[i], "brief", dev, 0, v
			i += 1
		if scn.scenarioName == "circleDrivingRev"
			task = runScenarioCurve scn, rx, ry, l, s, 1, false, false, leftParams[j], "brief", dev, 0, v
			j += 1
		if scn.scenarioName == "darkDriving"
			task = runScenarioCurve scn, rx, ry, l, s, 1, false, false, rightParamsDark[k], "dark", dev, 0, v
			k += 1
		if scn.scenarioName == "darkDrivingRev"
			task = runScenarioCurve scn, rx, ry, l, s, 1, false, false, leftParamsDark[h], "dark", dev, 0, v
			h += 1
		result = yield task.get \done
		result.outro \content .append $ L "<p>Kun olet valmis, jatka koetta painamalla ratin oikeaa punaista painiketta.</p>"
		yield task

	yield runWithNewEnv scenario.calibration, 3

	yield runWithNewEnv scenario.experimentOutro

export defaultExperiment = circleDrivingTrue

