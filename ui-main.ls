$ = require 'jquery'
deparam = require 'jquery-deparam'
P = require 'bluebird'
THREE = require 'three'
Signal = require 'signals'

{Scene, addGround, addSky} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{WsController} = require './controls.ls'
{IdmVehicle, LoopMicrosim, LoopPlotter} = require './microsim.ls'
{HudScreen} = require './hudscreen.ls'

Keypress = require 'keypress'

class MicrosimWrapper
	(@phys) ->
	position:~->
		@phys.position.z
	velocity:~->
		@phys.velocity.z

	step: ->

NonSteeringControl = (orig) ->
	ctrl = ^^orig
	ctrl.steering = 0
	return ctrl

{Catchthething} = require './catchthething.ls'

run = (opts) ->
	catchthething = new Catchthething $('#catchthething')

	renderer = new THREE.WebGLRenderer antialias: true
	renderer.autoClear = false
	scene = new Scene

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
	scene.afterPhysics.add traffic~step

	plotter = new LoopPlotter opts.loopContainer, traffic
	scene.onRender.add plotter~render
	scene.beforeRender.add -> renderer.clear()

	onSizeSignal = new Signal()
	onSizeSignal.size = [opts.container.width(), opts.container.height()]
	onSize = (handler) ->
		onSizeSignal.add handler
		handler ...onSizeSignal.size
	$(window).resize ->
		onSizeSignal.size = [opts.container.width(), opts.container.height()]
		onSizeSignal.dispatch ...onSizeSignal.size
	onSize (w, h) ->
		renderer.setSize window.innerWidth, window.innerHeight
	onSize (w, h) ->
		scene.camera.aspect = w/h
		scene.camera.updateProjectionMatrix()

	visualWorld = scene.visual
	camera = scene.camera
	renderDriving = ->
		renderer.render visualWorld, camera
	renderCatching = ->
		renderer.render catchthething.scene, catchthething.camera

	nullScene = new THREE.Scene
	renderBlank = ->
		renderer.render nullScene, camera
	doRender = renderDriving

	opts.container.mousedown (e) ->
		if e.which == 1
			catchthething.catch()
	opts.container.on "contextmenu", -> return false
	opts.container.mousedown (e) ->
		if e.which == 3
			doRender := renderCatching
		if e.which == 1
			catchthething.catch()

	opts.container.mouseup (e) ->
		if e.which == 3
			doRender := renderDriving


	scene.onRender.add (...args) -> doRender ...args

	opts.container.append renderer.domElement
	P.resolve addGround scene
	.then -> addSky scene
	.then -> WsController.Connect opts.controller
	.then (controls) ->
		controls = NonSteeringControl controls
		addVehicle scene, controls
	.then (player) ->
		player.eye.add scene.camera
		player.physical.position.x = -2.2
		scene.playerModel = player
		scene.playerVehicle = new MicrosimWrapper player.physical
			..higlight = true
		traffic.addVehicle scene.playerVehicle

		$('#currentSpeed').prop max: 120
		speedbar = $('#currentSpeed').prop "max", 200
		meanspeedbar = $('#meanSpeed').prop "max", 200
		cumspeed = 0
		cumtime = 0
		scene.afterPhysics.add (dt) ->
			position = scene.playerVehicle.position
			return if position < 1
			speed = scene.playerVehicle.velocity * 3.6
			speedbar.prop "value", speed
			cumtime += dt
			meanspeed = position/cumtime*3.6
			meanspeedbar.prop "value", meanspeed


	.then -> addVehicle scene
	.then (leader) ->
		leader.physical.position.z = scene.playerVehicle.leader.position
		leader.physical.position.x = -2.2
		scene.beforePhysics.add ->
			leader.physical.position.z = scene.playerVehicle.leader.position

	.then ->
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
		*/
		clock = new THREE.Clock
		tick = ->
			dt = clock.getDelta()
			scene.tick dt
			catchthething.tick dt
			requestAnimationFrame tick
		tick!


$ ->
	opts =
		container: $('#drivesim')
		loopContainer: $('#loopviz')
	opts <<< deparam window.location.search.substring 1
	run opts
