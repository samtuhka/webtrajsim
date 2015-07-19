P = require 'bluebird'
Co = P.coroutine
$ = require 'jquery'
seqr = require './seqr.ls'

{addGround, Scene} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{NonSteeringControl} = require './controls.ls'
{DefaultEngineSound} = require './sounds.ls'
assets = require './assets.ls'

# Just a placeholder for localization
L = (s) -> s

ui = require './ui.ls'

export baseScenario = seqr.bind ({controls, audioContext}) ->*
	scene = new Scene
	yield P.resolve addGround scene
	sky = yield P.resolve assets.addSky scene

	scene.playerControls = controls

	player = yield addVehicle scene, controls
	player.eye.add scene.camera
	player.physical.position.x = -1.75
	scene.player = player

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
	intro = ui.instructionScreen env, ->
		@ \title .text L "Warm up"
		@ \content .text L """
			Let's get started. In this task you'll get to know
			the basic controls. Just follow the instructions!
			"""

	scene = yield baseScenario env
	limits = [
		[10, 50]
		[200, 30]
		[300, 80]
		[500, 60]
	]

	for [dist, limit] in limits
		sign = yield assets.SpeedSign limit
		sign.position.z = dist
		sign.position.x = -4
		scene.visual.add sign

	scenario = env.SceneRunner scene
	yield scenario.get \ready
	intro.let \ready
	yield intro

	scenario.let \run

	yield ui.taskDialog env, Co ->*
		@ \title .text L "Speed up!"
		@ \content .text L "Use the throttle pedal to accelerate to 80 km/h."

		meter = $ L """<p>Current speed: <strong></strong> km/h</p>"""
		.appendTo @el
		.find \strong

		yield new P (accept) ->
			scene.onTickHandled.add ->
				speed = scene.player.getSpeed()*3.6
				meter.text Math.round speed
				if speed > 80
					accept()
		@ \content .text "Good job."
		yield P.delay 1000*3

	yield P.delay 1000*1

	yield ui.taskDialog env, Co ->*
		@ \title .text L "Stop!"
		@ \content .text L "Let's try the brake too. Use the brake pedal to stop the car."

		yield new P (accept) ->
			scene.onTickHandled.add ->
				speed = scene.player.getSpeed()*3.6
				if speed < 0.5
					accept()
		@ \content .text L "Good job again. That was the warm-up."
		yield P.delay 1000*5

	scenario.let \quit
	return scene

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
