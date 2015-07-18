$ = require 'jquery'
deparam = require 'jquery-deparam'
P = require 'bluebird'
Co = P.coroutine
seqr = require './seqr.ls'

{Signal} = require './signal.ls'
{KeyboardController, WsController} = require './controls.ls'
scenario = require './scenario.ls'
ui = require './ui.ls'

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


ScenarioRunner = seqr.bind (sceneLoader, env) ->*
	scene = yield sceneLoader env
	renderer = new THREE.WebGLRenderer antialias: true
	renderer.autoClear = false
	scene.beforeRender.add -> renderer.clear()

	render = -> renderer.render scene.visual, scene.camera
	scene.onRender.add render

	env.onSize (w, h) ->
		renderer.setSize w, h
		scene.camera.aspect = w/h
		scene.camera.updateProjectionMatrix()

	el = $ renderer.domElement
	env.container.append el
	render()
	yield ui.waitFor el~fadeIn
	@let \scene, scene
	yield @get \run
	quit = @get \quit
	scene.onStart.dispatch()

	yield eachFrame (dt) !->
		return true if not quit.isPending()
		scene.tick dt

	yield ui.waitFor el~fadeOut
	scene.onExit.dispatch()
	el~remove()

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
		SceneRunner: (scene) -> ScenarioRunner scene, env

	if opts.controller?
		env.controls = yield WsController.Connect opts.controller
	else
		env.controls = new KeyboardController

	yield scenario.freeRiding env
	#yield scenario.gettingStarted env
	#yield scenario.runTheLight env
	#yield scenario.runTheLight env
