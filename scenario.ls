P = require 'bluebird'
Co = P.coroutine

{addGround, addSky, Scene} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{NonSteeringControl} = require './controls.ls'
{DefaultEngineSound} = require './sounds.ls'

export baseScenario = Co ({controls, audioContext}) ->*
	scene = new Scene
	yield P.resolve addGround scene
	yield P.resolve addSky scene

	#controls = NonSteeringControl controls
	scene.playerControls = controls

	player = yield addVehicle scene, controls
	player.eye.add scene.camera
	player.physical.position.x = -1.75

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

	return scene
