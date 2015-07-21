$ = require 'jquery'
deparam = require 'jquery-deparam'
P = require 'bluebird'
Co = P.coroutine
seqr = require './seqr.ls'

{Signal} = require './signal.ls'
{KeyboardController, WsController} = require './controls.ls'
scenario = require './scenario.ls'
ui = require './ui.ls'

window.THREE = THREE
window.CANNON = require 'cannon'
require './node_modules/cannon/tools/threejs/CannonDebugRenderer.js'

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

	#physDebug = new THREE.CannonDebugRenderer scene.visual, scene.physics
	#scene.beforeRender.add ->
	#	physDebug.update()

	render = ->
		renderer.render scene.visual, scene.camera
	scene.onRender.add render

	env.onSize (w, h) ->
		renderer.setSize w, h
		scene.camera.aspect = w/h
		scene.camera.updateProjectionMatrix()
		render()

	el = $ renderer.domElement
	el.hide()
	env.container.append el
	yield P.resolve scene.preroll()
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

withEnv = seqr.bind ->*
	env = {}
	opts = {}
	opts <<< deparam window.location.search.substring 1

	container = $('#drivesim').empty().fadeIn()

	onSize = Signal onAdd: (cb) ->
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

	env.uiUpdate = Signal()
	id = setInterval env.uiUpdate.dispatch, 1/60*1000
	@finally -> clearInterval id
	env.SceneRunner = (scene) -> SceneRunner scene, env
	@let \env, env
	yield @get \destroy
	yield ui.waitFor container.fadeOut
	container.empty()

runScenario = seqr.bind (scenario) ->*
	scope = withEnv()
	@finally ->
		scope.let \destroy
	task = scenario yield scope.get \env
	yield task.get \done
	yield task

$ seqr.bind ->*
	#yield scenario.freeRiding env
	while true
		if not yield runScenario scenario.gettingStarted
			break
	#yield scenario.runTheLight env
	#yield scenario.runTheLight env
