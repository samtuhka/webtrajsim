$ = require 'jquery'
deparam = require 'jquery-deparam'
P = require 'bluebird'
Co = P.coroutine

{Signal} = require './signal.ls'
{KeyboardController, WsController} = require './controls.ls'
{baseScenario} = require './scenario.ls'

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


runScenario = Co (scene, env) ->*
	renderer = new THREE.WebGLRenderer antialias: true
	renderer.autoClear = false
	scene.beforeRender.add -> renderer.clear()
	scene.onRender.add ->
		renderer.render scene.visual, scene.camera
	env.onSize (w, h) ->
		renderer.setSize w, h
		scene.camera.aspect = w/h
		scene.camera.updateProjectionMatrix()

	env.container.empty()
	env.container.append renderer.domElement
	return yield eachFrame (dt) ->
		scene.tick dt
		if scene.time > 3*60
			return scene

$ Co ->*
	opts = {}
	opts <<< deparam window.location.search.substring 1

	container = $('#drivesim')
	onSizeSignal = new Signal()
	onSizeSignal.size = [container.width(), container.height()]
	onSize = (handler) ->
		onSizeSignal.add handler
		handler ...onSizeSignal.size
	$(window).resize ->
		onSizeSignal.size = [container.width(), container.height()]
		onSizeSignal.dispatch ...onSizeSignal.size

	env =
		container: container
		audioContext: new AudioContext
		onSize: onSize

	if opts.controller?
		env.controls = yield WsController.Connect opts.controller
	else
		env.controls = new KeyboardController

	scene = yield baseScenario env
	$('#drivesim').fadeIn(1000)
	$('#intro').fadeOut 1000, ->
		scene.onStart.dispatch()
	yield runScenario scene, env
	scene.onExit.dispatch()
