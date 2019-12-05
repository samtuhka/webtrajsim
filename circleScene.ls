P = require 'bluebird'
Co = P.coroutine
$ = require 'jquery'
seqr = require './seqr.ls'

{addCircleGround, Scene} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{NonSteeringControl} = require './controls.ls'
{DefaultEngineSound, BellPlayer, NoisePlayer} = require './sounds.ls'

assets = require './assets.ls'

# Just a placeholder for localization
L = (s) -> s

ui = require './ui.ls'

require './threex/threex.rendererstats.js'
require './threex/stats.js'

export circleScene = seqr.bind (env, params, control = true) ->*
	{controls, audioContext, L} = env
	scene = new Scene
	
	yield P.resolve addCircleGround scene, params.major_radius, params.minor_radius, params.length, params.hide, params.firstTurn, params.waypoint_n

	sky = yield P.resolve assets.addSky scene

	scene.playerControls = controls

	caropts =
		objectName: 'player'

	if env.opts.steeringNoise
		_cumnoise = 0.0
		caropts.steeringNoise = (dt) ->
			impulse = (Math.random() - 0.5)*2*0.01
			_cumnoise := 0.001*impulse + 0.999*_cumnoise

	#player = yield addVehicle scene, controls, caropts
	player = yield addVehicle scene, controls, "res/viva/2006-VIVA-VT3-Sedan-SE.dae", false, caropts
	player.eye.add scene.camera
	player.physical.position.x = scene.centerLine.getPointAt(0).y
	for i from 0 til player.body.children.length - 1
		player.body.children[i].visible = false
	scene.player = player

	scene.soundPlay = false
	scene.soundTs = 0
	scene.prevTime = 0
	scene.player.prevSpeed = 0
	scene.dT = 0
	scene.outside = {out: false, totalTime: 0}
	scene.scoring = {score: 0, missed: 0, trueYes: 0, falseYes: 0, trueNo: 0, falseNo: 0, maxScore: 0}
	scene.player.roadPhase = {direction: "None", phase: "None"}
	scene.end = false
	scene.player.pos = 0
	scene.player.minDist = 1000
	scene.player.react = false
	scene.predict = []
	for i from 0 til 5
		scene.predict.push new THREE.Vector3(0,0,0)
	scene.targetPresent = false
	scene.targetScreen = false
	scene.transientScreen = false
	scene.reacted = true
	scene.failed = false
	scene.startTime = 0
	scene.controlChange = false
	scene.prev = [0,0,0,0,0]


	engineSounds = yield DefaultEngineSound audioContext
	gainNode = audioContext.createGain()
	gainNode.connect audioContext.destination
	engineSounds.connect gainNode
	scene.prevGain = 0
	scene.afterPhysics.add ->
		rev = Math.abs(player.getSpeed())/(200/3.6)
		rev = Math.max 0.1, rev
		rev = (rev + 0.1)/1.1
		gain = scene.playerControls.throttle
		gain = (gain + 0.5)/1.5
		if Math.abs(gain - scene.prevGain) > 0.03
			gain = scene.prevGain + Math.sign(gain - scene.prevGain)*0.03


		scene.prevGain = gain
		gainNode.gain.value = gain
		engineSounds.setPitch rev*2000
	scene.onStart.add engineSounds.start
	scene.onExit.add engineSounds.stop

	scene.onStart ->
		env.container.addClass "hide-cursor"
	scene.onExit ->
		env.container.removeClass "hide-cursor"

	scene.preroll = seqr.bind ->*
		# Tick a couple of frames for the physics to settle
		t = Date.now()
		n = 100
		for [0 to n]
			# Make sure the car can't move during the preroll.
			# Yes, it's a hack
			controls
				..throttle = 0
				..brake = 0
				..steering = 0

			scene.tick 1/60
		console.log "Prewarming FPS", (n/(Date.now() - t)*1000)

	return scene
