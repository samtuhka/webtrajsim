$ = require 'jquery'
deparam = require 'jquery-deparam'
P = Promise = require 'bluebird'
Promise.config longStackTraces: true
Co = P.coroutine
seqr = require './seqr.ls'

{Signal} = require './signal.ls'
{KeyboardController, WsController} = require './controls.ls'
scenario = require './scenario.ls'
ui = require './ui.ls'

localizer = require './localizer.ls'

window.THREE = THREE = require 'three'
window.CANNON = require 'cannon'
require './node_modules/cannon/tools/threejs/CannonDebugRenderer.js'
doReQuestAnimationFrame = requestAnimationFrame 
eachFrame = (f) -> new P (accept, reject) ->
	stopped = false
	clock = new THREE.Clock
	tick = ->
		if stopped
			return
		doReQuestAnimationFrame tick
		dt = clock.getDelta()
		return if dt == 0
		result = f dt
		if result?
			accept result
			stopped := true
	tick()

audioContext = new AudioContext

{Sessions} = require './datalogger.ls'
_logger = void
getLogger = seqr.bind ->*
	if _logger?
		return _logger

	startTime = (new Date).toISOString()
	p = Sessions("wtsSessions")
	console.log p
	sessions = yield p
	_logger := yield sessions.create date: startTime
	return _logger

_wsLogger = void
wsLogger = seqr.bind (url) ->*
	if _wsLogger?
		return _wsLogger

	socket = yield new Promise (accept, reject) ->
		socket = new WebSocket url
		socket.onopen = -> accept socket
		socket.onerror = (ev) ->
			console.error "Failed to open logging socket", ev
			reject "Failed to open logging socket #url."
	_wsLogger :=
		write: (data) ->
			socket.send JSON.stringify do
				time: Date.now() / 1000
				data: data
		close: ->
			#socket.close()
	return _wsLogger


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
	lang = opts.lang ? 'en'
	yield env.L.load "locales/#{lang}.lson"

	container = $('#drivesim').empty().fadeIn()

	onSize = Signal onAdd: (cb) ->
		cb container.width(), container.height()
	dispatchResize = ->
		onSize.dispatch container.width(), container.height()
	$(window).on "resize", dispatchResize
	@finally !->
		$(window).off "resize", dispatchResize
		onSize.destroy()

	env <<<
		container: container
		audioContext: audioContext
		onSize: onSize
		opts: opts

	if not opts.disableDefaultLogger
		env.logger = yield getLogger!
	else
		env.logger =
			write: ->
			close: ->
	if opts.wsLogger?
		env.logger = yield wsLogger opts.wsLogger
	@finally ->
		env.logger.close()

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
		env.uiUpdate.destroy()

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
	@let \env, env
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
		# A hack to clear some caches in Cannon. Doesn't
		# clear everything.
		(new CANNON.World).step(1/20)
		# And similar hack for three.js
		renderer.render (new THREE.Scene), scene.camera
		renderer.dispose()
	#renderer.shadowMapEnabled = true
	#renderer.shadowMapType = THREE.PCFShadowMap
	renderer.autoClear = false
	scene.beforeRender.add -> renderer.clear()

	render = ->
		renderer.render scene.visual, scene.camera
	#if env.opts.enableVr
	render = enableVr env, renderer, scene

	#physDebug = new THREE.CannonDebugRenderer scene.visual, scene.physics
	#scene.beforeRender.add ->
	#	physDebug.update()


	scene.onRender.add render
	
	vrDump = (env, scene) ->
		vrDump = "vr not present"
		if env.vreffect.getVRDisplay()
			env.vreffect.getVRDisplay().getFrameData(env.frameData)
			frameData = env.frameData
			vrDump = 
				presenting: env.vreffect.isPresenting
				leftProjectionMatrix: frameData.leftProjectionMatrix
				leftViewMatrix: frameData.leftViewMatrix
				rightProjectionMatrix: frameData.rightProjectionMatrix
				rightViewMatrix: frameData.rightViewMatrix
				vrOrientation: frameData.pose.orientation
				vrPosition: frameData.pose.position
				vrTimestamp: frameData.timestamp
		return vrDump


	scene.onTickHandled ->
		dump =
			sceneTime: scene.time
			physics: dumpPhysics scene.physics
			camera:
				matrixWorldInverse: scene.camera.matrixWorldInverse.toArray()
				projectionMatrix: scene.camera.projectionMatrix.toArray()
			telemetry: env.controls{throttle, brake, steering, direction}
			vr: vrDump env, scene
		env.logger.write dump

	env.onSize (w, h) ->
		renderer.setSize w, h
		scene.camera.aspect = w/h
		scene.camera.updateProjectionMatrix()
		render()

	el = $ renderer.domElement
	el.hide()
	env.container.append el

	env.renderer = renderer
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
	{passed, outro} = result = yield scenario
	el.remove()

	#outro = ui.instructionScreen env, ->
	#		@ \title .append outro.title
	#		@ \subtitle .append outro.subtitle
	#		@ \content .append outro.content
	#		me.let \done, passed: passed, outro: @, result: result
	#@let \outro, [outro]
	#yield outro
	scope.let \destroy
	yield scope
	env.logger.write destroyedScenario: scenarioLoader.scenarioName

require './node_modules/three/examples/js/controls/VRControls.js'
require './node_modules/three/examples/js/effects/VREffect.js'
require './node_modules/three/examples/js/vr/WebVR.js'
#require './node_modules/webvr-boilerplate/js/deps/webvr-polyfill.js'
#require 'webvr-polyfill'
#require './node_modules/webvr-boilerplate/js/deps/VREffect.js'
#require './node_modules/webvr-boilerplate/js/deps/VRControls.js'
#WebVRManager = require './node_modules/webvr-boilerplate/src/webvr-manager.js'
#{keypress} = require 'keypress'

enableVr = (env, renderer, scene) ->
	vrcontrols = new THREE.VRControls scene.camera
	effect = env.vreffect = new THREE.VREffect renderer
	env.frameData = new VRFrameData()
	env.onSize (w, h) ->
		effect.setSize w, h
	vrcontrols.resetSensor()
	env.vrcontrols = vrcontrols
	effect.setFullScreen(true)
	env.container.append WEBVR.getButton(effect)
	doReQuestAnimationFrame := effect.requestAnimationFrame
	#WebVR.toggleVRMode()
	#manager = new WebVRManager renderer, effect
	#new keypress.Listener().simple_combo 'z', ->
	#	vrcontrols.resetSensor()
	#$("body")[0].addEventListener "click", ->
	#	effect.setFullScreen(true)
	#	#manager.toggleVRMode()
	scene.beforeRender.add ->
		vrcontrols.update()
	return -> effect.render scene.visual, scene.camera

