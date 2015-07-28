$ = require 'jquery'

seqr = require './seqr.ls'
{runScenario, newEnv} = require './scenarioRunner.ls'
scenario = require './scenario.ls'

L = (s) -> s

runUntilPassed = seqr.bind (scenarioLoader, {passes=2, maxRetries=5}={}) ->*
	currentPasses = 0
	for retry from 1 til Infinity
		task = runScenario scenarioLoader
		result = yield task.get \done
		currentPasses += result.passed

		doQuit = currentPasses >= passes or retry > maxRetries
		if not doQuit
			result.outro \content .append $ L "<p>Let's try that again.</p>"
		yield task
		if doQuit
			break



export mulsimco2015 = seqr.bind ->*
	env = newEnv!
	yield scenario.participantInformation yield env.get \env
	env.let \destroy
	yield env

	yield runScenario scenario.runTheLight

	yield runUntilPassed scenario.throttleAndBrake
	yield runUntilPassed scenario.speedControl

	yield runUntilPassed scenario.followInTraffic, passes: 5, maxRetries: 10

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

/*dummyScenario = seqr.bind (env) !->*
	#@let \scene,
	#	beforeRender: Signal!
	#	onRender: Signal!
	#	onStart: Signal!
	#	onExit: Signal!
	#	onTickHandled: Signal!
	#	camera: new THREE.PerspectiveCamera!
	#	visual: new THREE.Scene!
	#	preroll: ->
	#	tick: ->
	@let \scene, yield scenario.minimalScene env
	yield @get \run

	return passed: true, outro: {}

export memkiller = seqr.bind !->*
	for i from 1 to 100
		console.log i
		runner = runScenario scenario.followInTraffic
		[scn] = yield runner.get 'ready'
		console.log "Got scenario"
		[intro] = yield runner.get 'intro'
		if intro.let
			intro.let \accept
		scn.let 'done', passed: false, outro: title: "Yay"
		runner.let 'done'
		[outro] = yield runner.get 'outro'
		outro.let \accept
		console.log "Running"
		yield runner
		console.log "Done"
	return i*/
