$ = require 'jquery'
deparam = require 'jquery-deparam'
P = require 'bluebird'
THREE = require 'three'
Signal = require 'signals'

{Scene, addGround, addSky} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{WsController} = require './controls.ls'
{IdmVehicle, LoopMicrosim, LoopPlotter} = require './microsim.ls'

class MicrosimWrapper
	(@phys) ->
	position:~->
		@phys.position.z
	velocity:~->
		@phys.velocity.z
	
	step: ->

run = (opts) ->
	renderer = new THREE.WebGLRenderer antialias: true
	scene = new Scene

	nVehicles = 10
	spacePerVehicle = 20
	traffic = new LoopMicrosim nVehicles*spacePerVehicle
	for i in [1 til 10]
		v = new IdmVehicle
		v.position = i*spacePerVehicle
		traffic.addVehicle v
	scene.afterPhysics.add traffic~step
	
	console.log opts.loopContainer
	plotter = new LoopPlotter opts.loopContainer, traffic
	scene.onRender.add plotter~render

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

	scene.onRender.add ->
		renderer.render scene.visual, scene.camera
	opts.container.append renderer.domElement
	P.resolve addGround scene
	.then -> addSky scene
	.then -> WsController.Connect opts.controller
	.then (controls) -> addVehicle scene, controls
	.then (player) ->
		player.eye.add scene.camera
		player.physical.position.x = -2.3
		scene.playerVehicle = new MicrosimWrapper player.physical
			..higlight = true
		traffic.addVehicle scene.playerVehicle
	.then -> addVehicle scene
	.then (leader) ->
		leader.physical.position.z = scene.playerVehicle.leader.position
		leader.physical.position.x = -2.3
		scene.beforeRender.add ->
			leader.physical.position.z = scene.playerVehicle.leader.position
	.then ->
		clock = new THREE.Clock
		tick = ->
			scene.tick clock.getDelta()
			requestAnimationFrame tick
		tick!

$ ->
	opts =
		container: $('body')
		loopContainer: $('#loopviz')
	opts <<< deparam window.location.search.substring 1
	run opts
