$ = require 'jquery'
deparam = require 'jquery-deparam'
P = require 'bluebird'
THREE = require 'three'
Signal = require 'signals'

{Scene, addGround, addSky} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{WsController} = require './controls.ls'

run = (opts) ->
	renderer = new THREE.WebGLRenderer antialias: true
	scene = new Scene

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
	.then (vehicle) ->
		vehicle.eye.add scene.camera
		vehicle.physical.position.x = -2.3
	.then -> addVehicle scene
	.then (vehicle) ->
		vehicle.physical.position.z = 10
		vehicle.physical.position.x = -2.3
	.then ->
		clock = new THREE.Clock
		tick = ->
			scene.tick clock.getDelta()
			requestAnimationFrame tick
		tick!

$ ->
	opts =
		container: $('body')
	opts <<< deparam window.location.search.substring 1
	run opts
