P = require 'bluebird'
Co = P.coroutine
$ = require 'jquery'
seqr = require './seqr.ls'

{addCircleGround, Scene} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{NonSteeringControl} = require './controls.ls'
{DefaultEngineSound} = require './sounds.ls'
assets = require './assets.ls'

# Just a placeholder for localization
L = (s) -> s

ui = require './ui.ls'

export circleScene = seqr.bind (env, rx, ry, length) ->*
	{controls, audioContext} = env
	scene = new Scene
	yield P.resolve addCircleGround scene, rx, ry, length
	sky = yield P.resolve assets.addSky scene

	scene.playerControls = controls

	player = yield addVehicle scene, controls
	player.eye.add scene.camera
	player.physical.position.x = rx + 1.75
	player.body.visible = false
	scene.player = player
	scene.visual.children[9].visible = false
	scene.visual.children[8].visible = false
	scene.visual.children[7].visible = false
	scene.visual.children[6].visible = false
	scene.score = 0
	scene.soundPlay = false
	scene.soundTs = 0
	scene.prevTime = 0
	scene.player.prevSpeed = 0
	scene.dT = 0
	scene.maxScore = 0
	scene.player.speedometer = ui.gauge env,
		name: L "Score"
		unit: L "points"
		value: ->
			score = scene.score
	scene.player.speedometer2 = ui.gauge env,
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

