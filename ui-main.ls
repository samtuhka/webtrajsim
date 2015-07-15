$ = require 'jquery'
deparam = require 'jquery-deparam'
P = require 'bluebird'
Co = P.coroutine
THREE = require 'three'
{Signal} = require './signal.ls'

{Scene, addGround, addSky, loadTrafficLight} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{DefaultEngineSound} = require './sounds.ls'
{WsController, KeyboardController} = require './controls.ls'
{IdmVehicle, LoopMicrosim, LoopPlotter} = require './microsim.ls'

window.THREE = THREE
window.CANNON = require 'cannon'
require './node_modules/cannon/tools/threejs/CannonDebugRenderer.js'

Keypress = require 'keypress'
dbjs = require 'db.js'

class MicrosimWrapper
	(@phys) ->
	position:~->
		@phys.position.z
	velocity:~->
		@phys.velocity.z

	acceleration:~-> null

	step: ->

NonSteeringControl = (orig) ->
	ctrl = ^^orig
	ctrl.steering = 0
	return ctrl

{Catchthething} = require './catchthething.ls'
{Sessions} = require './datalogger.ls'

loadScene = Co (opts) ->*
	scene = new Scene

	renderer = new THREE.WebGLRenderer antialias: true
	renderer.autoClear = false
	scene.beforeRender.add -> renderer.clear()
	opts.container.append renderer.domElement

	nVehicles = 20
	spacePerVehicle = 20
	traffic = new LoopMicrosim nVehicles*spacePerVehicle
	for i in [1 til nVehicles]
		v = new IdmVehicle do
			a: 4.0
			b: 10.0
			timeHeadway: 1.0
		v.position = i*spacePerVehicle
		traffic.addVehicle v
	scene.beforePhysics.add traffic~step
	scene.traffic = traffic

	#plotter = new LoopPlotter opts.loopContainer, traffic
	#scene.onRender.add plotter~render

	#physDebug = new THREE.CannonDebugRenderer scene.visual, scene.physics
	#scene.beforeRender.add ->
	#	physDebug.update()

	onSizeSignal = new Signal()
	onSizeSignal.size = [opts.container.width(), opts.container.height()]
	onSize = (handler) ->
		onSizeSignal.add handler
		handler ...onSizeSignal.size
	$(window).resize ->
		onSizeSignal.size = [opts.container.width(), opts.container.height()]
		onSizeSignal.dispatch ...onSizeSignal.size
	onSize (w, h) ->
		renderer.setSize w, h
	onSize (w, h) ->
		scene.camera.aspect = w/h
		scene.camera.updateProjectionMatrix()

	visualWorld = scene.visual
	camera = scene.camera
	renderDriving = ->
		renderer.render visualWorld, camera
	#renderCatching = ->
	#	renderer.render catchthething.scene, catchthething.camera

	nullScene = new THREE.Scene
	renderBlank = ->
		renderer.render nullScene, camera
	doRender = renderDriving
	scene.onRender.add (...args) -> doRender ...args

	#scoreHud = $('#scoreHud')
	blinder = $('#blinder')
	onEyesOpened = new Signal
	onEyesClosed = new Signal
	scene.eyesOpen = true
	onEyesOpened.add !-> scene.eyesOpen := true
	onEyesClosed.add !-> scene.eyesOpen := false

	openEyes = ->
		onEyesOpened.dispatch()
		blinder.fadeOut 0.3*1000
	closeEyes = ->
		blinder.fadeIn 0.3*1000, -> onEyesClosed.dispatch()

	opts.container.on "contextmenu", -> return false

	scoreElement = $('#fuelConsumption')
	els =
		instantValue: $ '#instantScoreValue'
		instantBar: $ '#instantScoreBar' .prop min: 0, max: 40
		meanValue: $ '#meanScoreValue'
		meanBar: $ '#meanScoreBar' .prop min: 0, max: 40

	scene.beforeRender.add ->
		s = scene.scoring
		metersPerLiter = scene.scoring.distanceTraveled/scene.scoring.fuelConsumed
		litersPerMeter = 1.0/metersPerLiter
		litersPer100km = litersPerMeter*1000*100

		instMetersPerLiter = scene.playerVehicle.velocity/s.instantConsumption
		instLitersPer100km = (1.0/instMetersPerLiter)*1000*100

		moneyPerMeter = scene.scoring.moneyGathered/scene.scoring.distanceTraveled
		moneyPerHour = scene.scoring.moneyGathered/scene.scoring.scoreTime*60*60
		#scoreElement.text moneyPerHour

		instMoneyPerHour = s.moneyRate*60*60

		if isFinite instLitersPer100km and scene.playerVehicle.velocity > 1
			els.instantBar.val instLitersPer100km
			els.instantValue.text Math.round instLitersPer100km
		else
			els.instantBar.removeAttr 'value'
			els.instantValue.text "-"

		if isFinite litersPer100km and s.distanceTraveled > 10
			els.meanBar.val litersPer100km
			els.meanValue.text litersPer100km.toFixed 1
		#scoreElement.text "#{Math.round s.moneyRate*60*60*8} / #{Math.round moneyPerHour}"
		#scoreElement.text instLitersPer100km
		#scoreElement.text moneyPerMeter * 100*1000
		#scoreElement.text litersPer100km


	yield P.resolve addGround scene
	yield P.resolve addSky scene

	light = yield loadTrafficLight()
	light.visual.position.z = 6
	light.visual.position.x = -4
	light.visual.position.y = -1
	light.visual.rotation.y = Math.PI - 10*(Math.PI/180)
	light.addTo scene

	scene.onStart.add Co ->*
		yield P.delay 3*1000
		yield light.switchToGreen()

	if opts.controller?
		controls = yield WsController.Connect opts.controller
	else
		controls = new KeyboardController
	controls = NonSteeringControl controls
	controls.change.add (type, value) ->
		return if type != "blinder"
		if value
			closeEyes()
		else
			openEyes()
	scene.playerControls = controls
	player = yield addVehicle scene, controls
	player.eye.add scene.camera
	player.physical.position.x = -1.75

	scene.playerModel = player
	scene.playerVehicle = new MicrosimWrapper player.physical
		..higlight = true
	traffic.addVehicle scene.playerVehicle
	scene.playerModel.onCrash = new Signal
	player.physical.addEventListener "collide", (e) ->
		# TODO: Make sure ground collisions don't happen
		scene.playerModel.onCrash.dispatch e

	scene.scoring =
		scoreTime: 0
		cumulativeThrottle: 0
		fuelConsumed: 0
		instantConsumption: 0
	maximumFuelFlow = 200/60/1000
	constantConsumption = maximumFuelFlow*0.1
	fuelPrice = 1.5
	meterCompensation = 0.44/1000
	score = scene.scoring
	scene.afterPhysics.add (dt) ->
		score.scoreTime += dt
		score.instantConsumption = scene.playerControls.throttle*maximumFuelFlow + constantConsumption
		score.fuelConsumed += score.instantConsumption*dt
		score.distanceTraveled = scene.playerVehicle.position
		score.moneyRate = scene.playerVehicle.velocity*meterCompensation - score.instantConsumption*fuelPrice
		score.moneyGathered = score.distanceTraveled*meterCompensation - score.fuelConsumed*fuelPrice

	ctx = new AudioContext
	engineSounds = yield DefaultEngineSound ctx
	gainNode = ctx.createGain()
	gainNode.connect ctx.destination
	engineSounds.connect gainNode
	engineSounds.start()
	scene.afterPhysics.add ->
		rev = Math.abs(scene.playerModel.getSpeed())/(200/3.6)
		rev = Math.max 0.1, rev
		rev = (rev + 0.1)/1.1
		gain = scene.playerControls.throttle
		gain = (gain + 0.5)/1.5
		gainNode.gain.value = gain
		engineSounds.setPitch rev*2000
	scene.onExit.add ->
		engineSounds.stop()

	leader = yield addVehicle scene
	leader.physical.position.z = scene.playerVehicle.leader.position
	leader.physical.position.x = -1.75
	/*prevSpeed = 0
	leaderModel = scene.playerVehicle.leader
	scene.beforePhysics.add (dt) ->
		return if dt < 0
		speed = leader.getSpeed()
		accel = (speed - prevSpeed)/dt
		prevSpeed := speed
		delta = leaderModel.acceleration - accel
		adjust = delta/5.0
		adjust = Math.max -1, adjust
		adjust = Math.min 1, adjust
		if adjust > 0
			leader.controls.throttle = adjust
			leader.controls.brake = 0
		else
			leader.controls.throttle = 0
			leader.controls.brake = adjust*0.2
	*/

	scene.beforeRender.add (dt) ->
		leader.physical.position.z = scene.playerVehicle.leader.position
		leader.forceModelSync()

	return scene
	/*screenTarget = new THREE.WebGLRenderTarget 1024, 1024, format: THREE.RGBAFormat
		screenGeo = new THREE.PlaneGeometry 0.2, 0.2
		screenMat = new THREE.MeshBasicMaterial do
			map: screenTarget
			transparent: true
			alpha: 1
			alphaTest: 0.5
			blending: THREE.CustomBlending
		screen = new THREE.Mesh screenGeo, screenMat
			..position.x = 0.4 - 0.175
			..position.y = 1.25
			..position.z = 0.2
			..rotation.y = Math.PI
		scene.playerModel.body.add screen
		scene.beforeRender.add ->
			renderer.render catchthething.scene, catchthething.camera, screenTarget
			renderer.clear()
		return scene*/

eachFrame = (f) -> new P (accept, reject) ->
	clock = new THREE.Clock
	tick = ->
		dt = clock.getDelta()
		result = f dt
		if result?
			accept result
		else
			requestAnimationFrame tick
	tick()

$ Co ->*
	opts =
		container: $('#drivesim')
		loopContainer: $('#loopviz')
	opts <<< deparam window.location.search.substring 1

	scene = yield loadScene opts

	# Wait for the traffic to queue up
	while not scene.traffic.isInStandstill()
		scene.traffic.step 1/60
	# Tick a couple of frames for the physics to settle
	scene.tick 1/60
	n = 100
	t = Date.now()
	for [0 to n]
		scene.tick 1/60
	console.log "Prewarming FPS", (n/(Date.now() - t)*1000)

	run = Co (name) ->*
		startTime = (new Date).toISOString()
		$('#drivesim').fadeIn(1000)
		$('#intro').fadeOut 1000, ->
			scene.onStart.dispatch()
		sessions = yield Sessions("tbtSessions")
		logger = yield sessions.create do
					date: startTime
					name: name
		# WOW, really doesn't belong here!
		pluck = (obj, ...keys) ->
			dump = {}
			for key in keys
				dump[key] = obj[key]
			return dump

		dumpVehicle = (v) ->
			pluck v, \position, \velocity, \acceleration

		addEntry = (scene) ->
			logger.write do
				scene: pluck scene, \time, \eyesOpen
				player: dumpVehicle scene.playerVehicle
				leader: dumpVehicle scene.playerVehicle.leader
				controls: pluck scene.playerControls, \throttle, \brake, \steering, \direction
				scoring: scene.scoring


		yield eachFrame (dt) ->
			scene.tick dt
			if scene.time > 3*60
				return scene

		metersPerLiter = scene.scoring.distanceTraveled/scene.scoring.fuelConsumed
		litersPerMeter = 1.0/metersPerLiter
		litersPer100km = litersPerMeter*1000*100
		$('#finalScore').text litersPer100km.toFixed 1
		opts.container.fadeOut()
		$('#outro').fadeIn()
		scene.onExit.dispatch()

	$('#startbutton')
	.prop "disabled", false
	.text "Start!"
	.click -> run $('#sessionName').val()

