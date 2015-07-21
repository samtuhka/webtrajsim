P = require 'bluebird'
Co = P.coroutine
$ = require 'jquery'
seqr = require './seqr.ls'

{addGround, Scene} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{NonSteeringControl} = require './controls.ls'
{DefaultEngineSound} = require './sounds.ls'
assets = require './assets.ls'

{rfind} = require 'prelude-ls'

# Just a placeholder for localization
L = (s) -> s

ui = require './ui.ls'

export baseScenario = seqr.bind (env) ->*
	{controls, audioContext} = env
	scene = new Scene
	yield P.resolve addGround scene
	sky = yield P.resolve assets.addSky scene

	scene.playerControls = controls

	player = yield addVehicle scene, controls
	player.eye.add scene.camera
	player.physical.position.x = -1.75
	scene.player = player

	scene.player.speedometer = ui.gauge env,
		name: L "Speed"
		unit: L "km/h"
		value: ->
			speed = scene.player.getSpeed()*3.6
			Math.round speed

	engineSounds = yield DefaultEngineSound audioContext
	gainNode = audioContext.createGain()
	gainNode.connect audioContext.destination
	engineSounds.connect gainNode
	scene.afterPhysics.add ->
		rev = Math.abs(player.getSpeed())/(200/3.6)
		rev = Math.max 0.1, rev
		rev = (rev + 0.1)/1.1
		gain = scene.playerControls.throttle
		gain = (gain + 0.5)/1.5
		gainNode.gain.value = gain
		engineSounds.setPitch rev*2000
	scene.onStart.add engineSounds.start
	scene.onExit.add engineSounds.stop

	scene.preroll = ->
		# Tick a couple of frames for the physics to settle
		scene.tick 1/60
		n = 100
		t = Date.now()
		for [0 to n]
			scene.tick 1/60
		console.log "Prewarming FPS", (n/(Date.now() - t)*1000)
	return scene

export freeRiding = seqr.bind (env) ->*
	task = env.SceneRunner baseScenario
	task.let \run
	yield task

export basePedalScenario = (env) ->
	env = env with
		controls: NonSteeringControl env.controls
	return baseScenario env

export gettingStarted = seqr.bind (env) ->*
	name = L "Warm up"
	intro = ui.instructionScreen env, ->
		@ \title .text name
		@ \content .text L """
			Let's get started. In this task you should drive as fast
			as possible, yet honoring the speed limits.
			"""

	scene = yield basePedalScenario env
	limits = [
		[-Infinity, 50]
		[20, 50]
		[200, 30]
		[250, 80]
		[500, 60]
	]
	goalDistance = 700

	for [dist, limit] in limits
		sign = yield assets.SpeedSign limit
		sign.position.z = dist
		sign.position.x = -4
		scene.visual.add sign
	limits.reverse()
	currentLimit = ->
		mypos = scene.player.physical.position.z
		for [distance, limit] in limits
			break if distance < mypos

		return limit

	limitSign = ui.gauge env,
		name: L "Speed limit"
		unit: L "km/h"
		value: currentLimit

	illGains = 0
	scene.afterPhysics (dt) ->
		limit = currentLimit!
		speed = Math.abs scene.player.getSpeed()*3.6
		if speed > limit
			illGains += (speed - limit)*dt
			limitSign.warning()
		else
			limitSign.normal()

	startLight = yield assets.TrafficLight()
	startLight.position.x = -4
	startLight.position.z = 6
	startLight.addTo scene

	endLight = yield assets.TrafficLight()
	endLight.position.x = -4
	endLight.position.z = goalDistance + 10
	endLight.addTo scene

	scene.player.onCollision (e) ~>
		screen = ui.instructionScreen env, ->
			@ \title .text L "Oops!"
			@ \content .text L """
			You ran the red light! Let's try that again.
			"""
		screen.let \ready
		@let \done,
			screen: screen
			repeat: true
		return false

	finishSign = yield assets.FinishSign!
	finishSign.position.z = goalDistance
	scene.visual.add finishSign

	scenario = env.SceneRunner scene
	yield scenario.get \ready
	intro.let \ready
	yield intro

	scenario.let \run
	P.delay 1000
	.then ->
		startLight.switchToGreen()

	scene.onTickHandled ~>
		return if Math.abs(scene.player.getSpeed()) > 0.1
		return if scene.player.physical.position.z < goalDistance
		screen = ui.instructionScreen env, ->
			@ \title .text L "Passed!"
			@ \content .text L """
			Yeeee!! (TODO)
			"""
		screen.let \ready

		@let \done, [screen]
		return false

	{screen, repeat} = yield @get \done
	scenario.let \quit
	yield screen
	return repeat

export runTheLight = Co (env) ->*
	loader = env.SceneRunner basePedalScenario

	yield ui.instructionScreen env, ->
		@ \title .text L "Run the light"
		@ \subtitle .text L "(Just this once!)"
		@ \content .html $ L """
			<p>From here on you must honor the traffic light.
			But go ahead and run it once so you know what happens.</p>

			<p>Press enter or click the button below to continue.</p>
			"""
		return loader

	runner = yield loader
	scene = runner.scene
	task = runner.run()

	yield task.quit()
