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

export newEnv = seqr.bind ->*
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
		opts: opts

	if opts.controller?
		env.controls = yield WsController.Connect opts.controller
	else
		env.controls = new KeyboardController

	env.uiUpdate = Signal()
	id = setInterval env.uiUpdate.dispatch, 1/60*1000
	@finally -> clearInterval id
	@let \env, env
	yield @get \destroy
	yield ui.waitFor container~fadeOut
	container.empty()

export runScenario = seqr.bind (scenarioLoader) ->*
	scope = newEnv()
	env = yield scope.get \env
	# Setup
	env.notifications = $ '<div class="notifications">' .appendTo env.container
	scenario = scenarioLoader env

	intro = P.resolve undefined
	me = @
	scenario.get \intro .then (introContent) ->
		intro := ui.instructionScreen env, ->
			@ \title .append introContent.title
			@ \subtitle .append introContent.subtitle
			@ \content .append introContent.content
			me.get \ready

	scene = yield scenario.get \scene

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

	# Run
	yield P.resolve scene.preroll()
	yield ui.waitFor el~fadeIn
	@let \ready
	yield intro
	scenario.let \run

	done = scenario.get \done
	scene.onStart.dispatch()

	yield eachFrame (dt) !->
		return true if not done.isPending()
		scene.tick dt
	scene.onExit.dispatch()

	env.notifications.fadeOut()
	yield ui.waitFor el~fadeOut
	{passed, outro} = yield scenario
	el.remove()

	yield ui.instructionScreen env, ->
			@ \title .append outro.title
			@ \subtitle .append outro.subtitle
			@ \content .append outro.content
			me.let \done, passed: passed, outro: @
	scope.let \destroy
	yield scope
