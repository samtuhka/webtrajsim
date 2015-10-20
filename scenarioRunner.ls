$ = require 'jquery'
deparam = require 'jquery-deparam'
P = require 'bluebird'
Co = P.coroutine
seqr = require './seqr.ls'

{Signal} = require './signal.ls'
{KeyboardController, WsController} = require './controls.ls'
scenario = require './scenario.ls'
ui = require './ui.ls'

localizer = require './localizer.ls'

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

audioContext = new AudioContext

{Sessions} = require './datalogger.ls'
_logger = void
getLogger = seqr.bind ->*
	if _logger?
		return _logger

	startTime = (new Date).toISOString()
	sessions = yield Sessions("wtsSessions")
	_logger := yield sessions.create date: startTime
	return _logger

dumpPhysics = (world) ->
	ret = world{time}

	ret.bodies = for body in world.bodies
		id: body.id
		index: body.index
		position: body.position{x, y, z}
		quaternion: body.quaternion{x, y, z, w}
		velocity: body.velocity{x, y, z}
		angularVelocity: body.angularVelocity{x, y, z}
		objectClass: body.objectClass
		objectName: body.objectName

	return ret

export newEnv = seqr.bind !->*
	env = {}
	opts = {}
	opts <<< deparam window.location.search.substring 1

	env.L = localizer()
	yield env.L.load 'locales/fi.lson'

	container = $('#drivesim').empty().fadeIn()

	onSize = Signal onAdd: (cb) ->
		cb container.width(), container.height()
	dispatchResize = ->
		onSize.dispatch container.width(), container.height()
	$(window).on "resize", dispatchResize
	@finally !->
		$(window).off "resize", dispatchResize

	env <<<
		container: container
		audioContext: audioContext
		onSize: onSize
		opts: opts

	env.logger = yield getLogger!

	if opts.controller?
		env.controls = controls = yield WsController.Connect opts.controller
	else
		env.controls = new KeyboardController
	@finally ->
		env.controls.close()
	env.controls.change (...args) ->
		env.logger.write controlsChange: args

	env.uiUpdate = Signal()
	id = setInterval env.uiUpdate.dispatch, 1/60*1000
	@finally !->
		clearInterval id

	env.finally = @~finally

	@let \env, env
	yield @get \destroy
	yield ui.waitFor container~fadeOut
	container.empty()
	# Hint cg run
	if window.gc?
		window.gc()

export runScenario = seqr.bind (scenarioLoader, ...args) !->*
	scope = newEnv()
	env = yield scope.get \env
	# Setup
	env.notifications = $ '<div class="notifications">' .appendTo env.container
	env.logger.write loadingScenario: scenarioLoader.scenarioName
	scenario = scenarioLoader env, ...args


	intro = P.resolve undefined
	me = @
	scenario.get \intro .then (introContent) ->
		intro := ui.instructionScreen env, ->
			@ \title .append introContent.title
			@ \subtitle .append introContent.subtitle
			@ \content .append introContent.content
			# HACK!
			env.logger.write scenarioIntro: @el.html()
			me.get \ready

	scene = yield scenario.get \scene

	renderer = env.renderer = new THREE.WebGLRenderer antialias: true
	@finally ->
		THREE.Cache.clear()
		# A hack to clear some caches in Cannon
		(new CANNON.World).step(1/60)
	#renderer.shadowMapEnabled = true
	#renderer.shadowMapType = THREE.PCFShadowMap
	renderer.autoClear = false
	scene.beforeRender.add -> renderer.clear()

	render = ->
		renderer.render scene.visual, scene.camera
	if env.opts.enableVr
		render = enableVr env, renderer, scene

	#physDebug = new THREE.CannonDebugRenderer scene.visual, scene.physics
	#scene.beforeRender.add ->
	#	physDebug.update()


	scene.onRender.add render

	scene.onTickHandled ->
		dump =
			sceneTime: scene.time
			physics: dumpPhysics scene.physics
			camera:
				matrixWorldInverse: scene.camera.matrixWorldInverse.toArray()
				projectionMatrix: scene.camera.projectionMatrix.toArray()
			telemetry: env.controls{throttle, brake, steering, direction}
		env.logger.write dump

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
	@let \ready, [scenario]
	@let \intro, [intro]
	yield intro
	scenario.let \run

	done = scenario.get \done
	env.logger.write startingScenario: scenarioLoader.scenarioName
	scene.onStart.dispatch()

	yield eachFrame (dt) !->
		return true if not done.isPending()
		scene.tick dt
	scene.onExit.dispatch()
	env.logger.write exitedScenario: scenarioLoader.scenarioName

	env.notifications.fadeOut()
	yield ui.waitFor el~fadeOut
	{passed, outro} = yield scenario
	el.remove()

	outro = ui.instructionScreen env, ->
			@ \title .append outro.title
			@ \subtitle .append outro.subtitle
			@ \content .append outro.content
			me.let \done, passed: passed, outro: @
	@let \outro, [outro]
	yield outro
	scope.let \destroy
	yield scope
	env.logger.write destroyedScenario: scenarioLoader.scenarioName

#require './three.js/examples/js/controls/VRControls.js'
#require './three.js/examples/js/effects/VREffect.js'
#require './node_modules/webvr-boilerplate/js/deps/webvr-polyfill.js'
/*require 'webvr-polyfill'
require './node_modules/webvr-boilerplate/js/deps/VREffect.js'
require './node_modules/webvr-boilerplate/js/deps/VRControls.js'
WebVRManager = require './node_modules/webvr-boilerplate/src/webvr-manager.js'
{keypress} = require 'keypress'

enableVr = (env, renderer, scene) ->
	vrcontrols = new THREE.VRControls scene.camera
	effect = new THREE.VREffect renderer
	env.onSize (w, h) ->
		effect.setSize w, h
	manager = new WebVRManager renderer, effect
	new keypress.Listener().simple_combo 'z', ->
		vrcontrols.resetSensor()
	#$("body")[0].addEventListener "click", ->
	#	effect.setFullScreen(true)
	#	#manager.toggleVRMode()
	scene.beforeRender.add ->
		vrcontrols.update()
	return -> manager.render scene.visual, scene.camera
*/
