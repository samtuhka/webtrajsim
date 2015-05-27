$ = require 'jquery'
{map} = require 'prelude-ls'
Promise = require 'bluebird'
#require !webpack
#require 'script!webvr-boilerplate/js/deps/three.js'
#new webpack.ProvidePlugin do
#	three: './three.js/build/three.js'

#THREE = require 'three'
#window.THREE = THREE

#new webpack.DefinePlugin do
#	THREE: THREE

#window.THREE = require './three.js/build/three.js'
window.THREE = require 'three'
require 'script!./three.js/examples/js/loaders/BinaryLoader.js'
require 'script!./three.js/examples/js/loaders/UTF8Loader.js'
require 'script!./three.js/examples/js/loaders/DDSLoader.js'
require 'script!./three.js/examples/js/loaders/MTLLoader.js'

require 'script!./three.js/examples/js/controls/FlyControls.js'
require 'script!./three.js/examples/js/controls/TrackballControls.js'
require 'script!./three.js/examples/js/controls/OrbitControls.js'

require 'script!./three.js/examples/js/SkyShader.js'
require 'script!./three.js/examples/js/postprocessing/EffectComposer.js'
require 'script!./three.js/examples/js/shaders/CopyShader.js'
require 'script!./three.js/examples/js/postprocessing/RenderPass.js'
require 'script!./three.js/examples/js/postprocessing/MaskPass.js'
require 'script!./three.js/examples/js/postprocessing/ShaderPass.js'
require 'script!./three.js/examples/js/postprocessing/BloomPass.js'
require 'script!./three.js/examples/js/shaders/FXAAShader.js'
require 'script!./three.js/examples/js/shaders/SSAOShader.js'
require 'script!./three.js/examples/js/shaders/ConvolutionShader.js'

{Signal} = require 'signals'
window.CANNON = Cannon = require 'cannon'
require 'script!cannon/tools/threejs/CannonDebugRenderer.js'
Keypress = require 'keypress'

deparam = require 'jquery-deparam'

require 'script!./three.js/examples/js/controls/VRControls.js'
#require 'script!webvr-boilerplate/js/deps/VREffect.js'
require 'script!./three.js/examples/js/effects/VREffect.js'
require 'script!webvr-boilerplate/js/deps/webvr-polyfill.js'
require 'script!webvr-boilerplate/build/webvr-manager.js'

require 'script!./three.js/examples/js/libs/stats.min.js'

{PLoader} = require './ThreePromise.ls'

t = require './terrainLoader.ls'

#.then (stuff) ->
#	console.log stuff

class KeyboardController
	->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1
		@listener = new Keypress.Listener
		@listener.register_combo do
			keys: 'w'
			on_keydown: ~> @throttle = 1;
			on_keyup: ~> @throttle = 0
		@listener.register_combo do
			keys: 's'
			on_keydown: ~> @brake = 1;
			on_keyup: ~> @brake = 0

		@listener.register_combo do
			keys: 'a'
			on_keydown: ~> @steering = 1;
			on_keyup: ~> @steering = 0

		@listener.register_combo do
			keys: 'd'
			on_keydown: ~> @steering = -1;
			on_keyup: ~> @steering = 0

		@listener.simple_combo 'w', -> console.log "w"

class MouseController
	(el) ->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1
		el.mousemove (ev) ~>
			x = ev.pageX
			x /= window.innerWidth
			x *= 2
			x -= 1
			@steering = -x

			y = ev.pageY
			y /= window.innerHeight
			y *= 2
			y -= 1
			y = -y
			if y > 0
				@throttle = y
				@brake = 0
			else
				@throttle = 0
				@brake = -y

class WsController
	(socketUrl) ->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1
		@socket = new WebSocket socketUrl
		@socket.onmessage = (msg) ~>
			@ <<< JSON.parse msg.data

		@ready = false
		@connected = new Signal()
		@socket.onopen = ~>
			@ready = true
			@connected.dispatch()

	set: (obj) ->
		return if not @ready
		@socket.send JSON.stringify obj

generateTerrain = (heightmap) ->
	return
	heightmap <- (new THREE.ImageLoader) .load heightmap
	canvas = document.createElement('canvas')
		..width = heightmap.width
		..height = heigthmap.height


runScene = (opts) ->
	onSizeSignal = new Signal()
	console.log opts.container.width(), opts.container.height()
	onSizeSignal.size = [opts.container.width(), opts.container.height()]
	onSize = (handler) ->
		onSizeSignal.add handler
		handler ...onSizeSignal.size
	$(window).resize ->
		onSizeSignal.size = [opts.container.width(), opts.container.height()]
		onSizeSignal.dispatch ...onSizeSignal.size

	ctrl =
		physGraphMap: new Map
		bindPhys: (phys, graph) ->
			@physGraphMap.set phys, graph

		tick: (dt) ->
			@onUpdate.dispatch dt
			@world.step 1/60, dt
			@physGraphMap.forEach (graph, phys) ->
				graph.position.copy phys.position
				graph.quaternion.copy phys.quaternion
			@afterPhysics.dispatch dt
			@beforeRender.dispatch dt
			@render!
			@afterUpdate.dispatch dt

		clock: new THREE.Clock

		onUpdate: new Signal
		afterUpdate: new Signal
		afterPhysics: new Signal
		beforeRender: new Signal

		start: ->
			tick = ~>
				@tick @clock.getDelta()
				requestAnimationFrame(tick)
			tick()

	ctrl.world = world = new Cannon.World
		..gravity.set 0, -9.81, 0
		#..gravity.set 0, 0, 0
		..defaultContactMaterial
			..friction = 10
			..restitution = 0.3
		..solver.iterations = 10
		..broadphase = new CANNON.SAPBroadphase world

	ctrl.scene = scene = new THREE.Scene
	ctrl.renderer = renderer = new THREE.WebGLRenderer antialias: false
	renderer.getSize = ->
		s = onSizeSignal.size
		width: s[0], height: s[1]
	renderer.setPixelRatio window.devicePixelRatio
	onSize (w, h) ->
		renderer.setSize window.innerWidth, window.innerHeight
	opts.container.append renderer.domElement
	#debugRenderer = new THREE.CannonDebugRenderer scene, world
	#ctrl.afterPhysics.add -> debugRenderer.update!

	god_camera = new THREE.PerspectiveCamera 40, window.innerWidth/window.innerHeight, 0.01, 450000
	#god_camera.rotation.y = Math.PI
	#god_camera.position.y = Math.PI
	#god_camera.rotation.x = -Math.PI/2
	god_camera.position.y = 10
	god_controls = new THREE.OrbitControls god_camera, renderer.domElement
	ctrl.onUpdate.add god_controls~update

	driver_camera = new THREE.PerspectiveCamera 50, 1, 0.01, 450000
	onSize (w, h) ->
		driver_camera.aspect = w/h
		driver_camera.updateProjectionMatrix()
	ctrl.camera = camera = driver_camera

	/*{getTerrain} = require './terrainLoader.ls'
	tp = getTerrain do
		hUrl: 'res/world/heightmap.png'
		hscale: 100
		xyscale: 5.0
		texUrl: 'res/terrain/texture.jpg'
		texSize: 5
		renderer: renderer

	terrain <- tp.then
	world.add terrain.phys
	scene.add terrain.mesh*/

	groundTex = THREE.ImageUtils.loadTexture 'res/world/sandtexture.jpg'
	terrainSize = 10000
	textureSize = 5
	textureRep = terrainSize/textureSize
	groundNorm = THREE.ImageUtils.loadTexture 'res/world/sandtexture.norm.jpg'
	groundTex.wrapS = groundTex.wrapT = THREE.RepeatWrapping
	groundNorm.wrapS = groundNorm.wrapT = THREE.RepeatWrapping
	groundTex.repeat.set textureRep, textureRep
	groundNorm.repeat.set textureRep, textureRep
	groundTex.anisotropy = renderer.getMaxAnisotropy()
	groundMaterial = new THREE.MeshPhongMaterial do
		color: 0xffffff
		map: groundTex
		normalMap: groundNorm

	groundGeometry = new THREE.PlaneGeometry terrainSize, terrainSize, 0, 0
	ground = new THREE.Mesh groundGeometry, groundMaterial
	ground.rotation.x = -Math.PI/2.0
	# To avoid z-fighting. Should be handled by
	# polygon offset, but it gives very weird results
	ground.position.y = -0.1
	groundBody = new Cannon.Body mass: 0
		..addShape new Cannon.Plane
		..quaternion.setFromAxisAngle new Cannon.Vec3(1,0,0), -Math.PI/2.0
	scene.add ground
	world.add groundBody

	roadWidth = 10
	roadGeo = new THREE.PlaneGeometry terrainSize, roadWidth, 0, 0
	roadTex = THREE.ImageUtils.loadTexture 'res/world/road_texture.jpg'
	roadNorm = THREE.ImageUtils.loadTexture 'res/world/road_texture.norm.jpg'
	roadTex.anisotropy = renderer.getMaxAnisotropy()
	#roadTex.minFilter = THREE.LinearMipMapLinearFilter
	roadTex.minFilter = THREE.LinearFilter
	roadTex.wrapS = roadTex.wrapT = THREE.RepeatWrapping
	roadNorm.wrapS = roadNorm.wrapT = THREE.RepeatWrapping
	roadTex.repeat.set textureRep/2.0, 1
	roadNorm.repeat.set textureRep/2.0, 1
	roadMat = new THREE.MeshPhongMaterial do
		map: roadTex
		#normalMap: roadNorm
	road = new THREE.Mesh roadGeo, roadMat
	road.rotation.x = -Math.PI/2.0
	road.rotation.z = -Math.PI/2.0
	road.position.y = 0
	scene.add road

	sky = new THREE.Sky
	sky.uniforms.sunPosition.value.y = 400
	scene.add sky.mesh

	sunlight = new THREE.DirectionalLight 0xffffff, 0.5
	sunlight.position.set 0, 1, 0
	scene.add sunlight
	hemiLight = new THREE.HemisphereLight 0xffffff, 0xffffff, 0.3
		..position.set 0, 4500, 0
	scene.add hemiLight
	#ambientLight = new THREE.AmbientLight( 0x222222 );
	#scene.add ambientLight

	/*composer = new THREE.EffectComposer renderer
	composer.addPass new THREE.RenderPass scene, camera


	#bloom = new THREE.BloomPass 1
	#composer.addPass bloom
	#ctrl.beforeRender.add -> renderer.clear!

	depthShader = THREE.ShaderLib.depthRGBA
	depthUniforms = THREE.UniformsUtils.clone depthShader.uniforms
	depthMaterial = new THREE.ShaderMaterial do
		fragmentShader: depthShader.fragmentShader
		vertexShader: depthShader.vertexShader
		uniforms: depthUniforms
		blending: THREE.NoBlending


	depthTarget = new THREE.WebGLRenderTarget window.innerWidth, window.innerHeight, {minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter, format: THREE.RGBAFormat}
	ssao = new THREE.ShaderPass THREE.SSAOShader
	ssaoClip = near: 0.01, far: 100
	ssao.uniforms.tDepth.value = depthTarget
	ssao.uniforms.size.value.set window.innerWidth, window.innerHeight
	ssao.uniforms.cameraNear.value = ssaoClip.near
	ssao.uniforms.cameraFar.value = ssaoClip.far
	ssao.uniforms.aoClamp.value = 0.5
	ssao.uniforms.lumInfluence.value = 0.5
	ssao.uniforms.onlyAO.value = 0
	ssaoCamera = camera with ssaoClip
	ctrl.beforeRender.add ->
		m = scene.overrideMaterial
		scene.overrideMaterial = depthMaterial
		renderer.render scene, ssaoCamera, depthTarget
		scene.overrideMaterial = m
	composer.addPass ssao

	fxaa = new THREE.ShaderPass THREE.FXAAShader
	fxaa.uniforms.resolution.value.set 1/window.innerWidth, 1/window.innerHeight
	composer.addPass fxaa



	composer.passes[*-1].renderToScreen = true
	ctrl.render = ->
		#renderer.render scene, camera
		composer.render()
	*/

	do ->
		vrcontrols = new THREE.VRControls driver_camera
		effect = new THREE.VREffect renderer
		onSize (w, h) ->
			effect.setSize w, h
		manager = new WebVRManager renderer, effect, hideButton: true
		new Keypress.Listener().simple_combo 'f', ->
			manager.toggleVRMode()
		ctrl.onUpdate.add ->
			vrcontrols.update()
		ctrl.render = ->
			scene.updateMatrixWorld()
			#effect.render scene, camera
			manager.render scene, camera
		#ctrl.render()

	THREE.Loader.Handlers.add /\.dds$/i, (new THREE.DDSLoader());
	#(new THREE.BinaryLoader).load 'res/camaro/CamaroNoUv_bin.js', (o, m) ->
	#(new THREE.JSONLoader).load 'res/camaro/blend/body.json', (o, m) ->
	Promise.props do
		body: (PLoader THREE.JSONLoader) 'res/camaro/blend/body.json'
		#body: (PLoader THREE.ObjectLoader) 'res/corolla/body.json'
		wheel: (PLoader THREE.JSONLoader) 'res/camaro/blend/wheel.json'
	.then ({body, wheel}) ->
		[o, m] = body
		[w, wm] = wheel
		#console.log o, m
		#w, wm <- (new THREE.JSONLoader).load 'res/camaro/blend/wheel.json'

		#(new THREE.ObjectLoader).load 'res/camaro/blend/camaro_body.json', (s) ->
		#console.log o
		#console.log m

		w.computeBoundingBox()
		wRadius = w.boundingBox.max.z
		wWidth = w.boundingBox.max.x*2

		o.computeBoundingBox()
		bbox = o.boundingBox
		bbox.min.y += 0.3
		halfbox = new Cannon.Vec3().copy bbox.max.clone().sub(bbox.min).divideScalar 2
		body = new THREE.Mesh o, (new THREE.MeshFaceMaterial m)
		scene.add body

		offOrigin = new Cannon.Vec3().copy bbox.min.clone().add(bbox.max).divideScalar 2

		bodyPhys = new Cannon.Body mass: 2000
			..addShape (new Cannon.Box halfbox), offOrigin
			..linearDamping = 0.1
			..angularDamping = 0.1
		ctrl.bindPhys bodyPhys, body

		car = new Cannon.RaycastVehicle do
			chassisBody: bodyPhys
			indexRightAxis: 0
			indexForwardAxis: 2
			indexUpAxis: 1

		#controls = new MouseController $ 'body'
		controls = new WsController opts.controller

		enginePower = 6000
		brakePower = 100
		maxSteer = 0.8
		maxCentering = 0.4
		maxCenteringSpeed = 10
		steeringDeadzone = 0.005

		#ctrl.afterPhysics.add ->
		#	centering = (bodyPhys.velocity.norm()/maxCenteringSpeed)*maxCentering
		#	centering = Math.min centering, maxCentering
		#	controls.set autocenter: centering
		controls.connected.add ->
			controls.set autocenter: 0.6


		wheelPositions = [
			[0.83, 0.0, 1.52],
			[-0.83, 0.0, 1.52],
			[0.83, 0.0, -1.45],
			[-0.83, 0.0, -1.45],
		]
		for let [x, y, z] in wheelPositions
			wii = car.addWheel do
				radius: wRadius
				directionLocal: new Cannon.Vec3 0, -1, 0
				axleLocal: new Cannon.Vec3 -1, 0, 0
				suspensionRestLength: wRadius + 0.25
				chassisConnectionPointLocal: new Cannon.Vec3(x, y, z).vadd offOrigin
				suspensionStiffness: 100
				rollInfluence: 1
				frictionSlip: 1000
			wi = car.wheelInfos[wii]
			wheel = new THREE.Mesh w, new THREE.MeshFaceMaterial wm
			if x < 0
				tmp = new THREE.Object3D
				wheel.rotation.y = Math.PI
				tmp.add wheel
				wheel = tmp

			scene.add wheel

			ctrl.afterPhysics.add ->
				car.updateWheelTransform wii
				wheel.position.copy wi.worldTransform.position
				wheel.quaternion.copy wi.worldTransform.quaternion

			ctrl.onUpdate.add ->
				wi.brake = brakePower*controls.brake
				mag = Math.abs controls.steering
				dir = Math.sign controls.steering
				mag -= steeringDeadzone
				mag = Math.max mag, 0
				steering = mag*dir*maxSteer
				if z > 0
					# Front wheels
					wi.steering = maxSteer*steering
					# Back wheels
					wi.engineForce = -enginePower*controls.throttle*controls.direction
				else
					#

		car.addToWorld world
		bodyPhys.position.y = 1
		#worldbox = new THREE.Box3! .setFromObject terrain.mesh
		#bodyPhys.position.x = worldbox.max.x*0.73
		#bodyPhys.position.z = -10

		eye = new THREE.Object3D
		eye.position.x = 0.4
		eye.position.y = 1.25
		#eye.position.z = -0.1
		eye.position.z = 0.6
		eye.rotation.y = Math.PI
		#camera.rotation.y = Math.PI

		/*eye.position.x = 2
		eye.position.z = -2
		eye.position.y = 2
		eye.lookAt new THREE.Vector3 0, 0, 0*/
		eye.add driver_camera
		body.add eye

	/*
	render = ->
		requestAnimationFrame render
		god_controls.update!

		#scene.overrideMaterial = depthMaterial
		#renderer.render scene, camera, depthTarget
		#scene.overrideMaterial = null
		#composer.render()

		renderer.render scene, camera
	render()*/
	ctrl.start!
	stats = new Stats
	ctrl.onUpdate.add -> stats.begin()
	ctrl.afterUpdate.add -> stats.end()
	$(stats.domElement)
	.appendTo opts.container
	.css do
		position: 'absolute'
		left: 0
		top: 0
	new Keypress.Listener().simple_combo 's', ->
		console.log $('#fpsText').text()
$ ->
	opts =
		container: $('body')
	opts <<< deparam window.location.search.substring 1
	runScene opts
