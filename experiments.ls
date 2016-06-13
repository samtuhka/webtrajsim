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
	env.i = 0
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


export paavoDriving = seqr.bind ->*

#  s1r1 = kiertonopeus 1 radalla 1

	s1r1 = 20
	s1r2 = 41

	s2r1 = 31
	s2r2 = 61

	s3r1 = 41
	s3r2 = 82

	yield runScenario scenario.circle, 25, s1r1, 20
	yield runScenario scenario.circleRev, 25, s1r1, 20
	yield runScenario scenario.circle, 25, s1r2, 20
	yield runScenario scenario.circleRev, 25, s1r2, 20
	yield runScenario scenario.circle, 25, s2r1, 20
	yield runScenario scenario.circleRev, 25, s2r1, 20
	yield runScenario scenario.circle, 25, s2r2, 20
	yield runScenario scenario.circleRev, 25, s2r2, 20
	yield runScenario scenario.circle, 50, s3r1, 20
	yield runScenario scenario.circleRev, 50, s3r1, 20
	yield runScenario scenario.circle, 50, s3r2, 20
	yield runScenario scenario.circleRev, 50, s3r2, 20


export paavoDrivingRandom = seqr.bind ->*

#  s1r1 = kiertonopeus 1 radalla 1

	s1r1 = 20
	s1r2 = 41

	s2r1 = 31
	s2r2 = 61

	s3r1 = 41
	s3r2 = 82


	scenarios = []
		.concat({'scene': scenario.circle, 'rx': 25, 's': s1r1, 'dur': 20})
		.concat({'scene': scenario.circleRev, 'rx': 25, 's': s1r1, 'dur': 20})
		.concat({'scene': scenario.circle, 'rx': 25, 's': s1r2, 'dur': 20})
		.concat({'scene': scenario.circleRev, 'rx': 25, 's': s1r2, 'dur': 20})
		.concat({'scene': scenario.circle, 'rx': 25, 's': s2r1, 'dur': 20})
		.concat({'scene': scenario.circleRev, 'rx': 50, 's': s2r1, 'dur': 20})
		.concat({'scene': scenario.circle, 'rx': 50, 's': s2r2, 'dur': 20})
		.concat({'scene': scenario.circleRev, 'rx': 50, 's': s2r2, 'dur': 20})
		.concat({'scene': scenario.circle, 'rx': 50, 's': s3r1, 'dur': 20})
		.concat({'scene': scenario.circleRev, 'rx': 50, 's': s3r1, 'dur': 20})
		.concat({'scene': scenario.circle, 'rx': 50, 's': s3r2, 'dur': 20})
		.concat({'scene': scenario.circleRev, 'rx': 50, 's': s3r2, 'dur': 20})

	scenarios = shuffleArray scenarios
	for scn in scenarios
		yield runScenario scn.scene, scn.rx, scn.s, scn.dur


