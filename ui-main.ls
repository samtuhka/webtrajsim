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


SceneRunner = seqr.bind (scene, env) ->*
	renderer = new THREE.WebGLRenderer antialias: true
	#renderer.shadowMapEnabled = true
	#renderer.shadowMapType = THREE.PCFShadowMap
	renderer.autoClear = false
	scene.beforeRender.add -> renderer.clear()

	render = ->
		renderer.render scene.visual, scene.camera
	scene.onRender.add render

	env.onSize (w, h) ->
		renderer.setSize w, h
		scene.camera.aspect = w/h
		scene.camera.updateProjectionMatrix()
		render()

	el = $ renderer.domElement
	env.container.append el
	render()
	yield ui.waitFor el~fadeIn
	@let \ready
	yield @get \run
	quit = @get \quit
	scene.onStart.dispatch()

	yield eachFrame (dt) !->
		return true if not quit.isPending()
		scene.tick dt

	yield ui.waitFor el~fadeOut
	scene.onExit.dispatch()
	el.remove()
	return scene

Env = -> new ->
	onDestroy = Signal()
	isDestroyed = false
	@Signal = (...args) ->
		signal = new Signal ...args
		onDestroy ->
			signal.destroy()
		return signal

	@callback = (f) -> (...args) ->
		if isDestroyed
			return false
		return f ...args

	@destroy = ->
		onDestroy.dispatch()
		onDestroy.destroy()
		isDestroyed = true

withEnv = seqr.bind ->*
	env = Env!
	opts = {}
	opts <<< deparam window.location.search.substring 1

	container = $('#drivesim').empty()
	@finally ->
		$('#drivesim').empty()

	onSize = env.Signal onAdd: (cb) ->
		cb container.width(), container.height()
	$(window).resize ->
		onSize.dispatch container.width(), container.height()

	env <<<
		container: container
		audioContext: new AudioContext
		onSize: onSize
		notifications: $ '<div class="notifications">' .appendTo container

	if opts.controller?
		env.controls = yield WsController.Connect opts.controller
	else
		env.controls = new KeyboardController

	env.uiUpdate = env.Signal!
	setInterval env.uiUpdate.dispatch, 1/60*1000
	env.SceneRunner = (scene) -> SceneRunner scene, env
	@let \env, env
	yield @get \destroy
	env.destroy()

runScenario = seqr.bind (scenario) ->*
	scope = withEnv()
	@finally ->
		scope.let \destroy
	return yield scenario yield scope.get \env

$ seqr.bind ->*
	#yield scenario.freeRiding env
	yield runScenario scenario.gettingStarted
	#yield scenario.runTheLight env
	#yield scenario.runTheLight env
