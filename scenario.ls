P = require 'bluebird'
Co = P.coroutine
$ = require 'jquery'
seqr = require './seqr.ls'


{addGround, Scene} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{NonSteeringControl} = require './controls.ls'
{DefaultEngineSound, BellPlayer, NoisePlayer} = require './sounds.ls'
assets = require './assets.ls'
prelude = require 'prelude-ls'

ui = require './ui.ls'

exportScenario = (name, impl) ->
	scn = seqr.bind impl
	scn.scenarioName = name
	module.exports[name] = scn
	return scn

DummyScene = ->
	beforePhysics: Signal!
	afterPhysics: Signal!
	beforeRender: Signal!
	onRender: Signal!
	onStart: Signal!
	onExit: Signal!
	onTickHandled: Signal!
	#camera: new THREE.PerspectiveCamera!
	camera:
		updateProjectionMatrix: ->
		add: ->
	#visual: new THREE.Scene!
	visual:
		add: ->
		traverse: ->
		addEventListener: ->
	physics:
		add: ->
		addEventListener: ->
		removeBody: ->
	preroll: ->
	tick: ->
	bindPhys: ->
#Scene = DummyScene

export baseScene = seqr.bind (env) ->*
	{controls, audioContext, L} = env
	scene = new Scene
	yield P.resolve addGround scene
	sky = yield P.resolve assets.addSky scene

	scene.playerControls = controls

	caropts =
		objectName: 'player'

	if env.opts.steeringNoise
		_cumnoise = 0.0
		caropts.steeringNoise = (dt) ->
			impulse = (Math.random() - 0.5)*2*0.01
			_cumnoise := 0.001*impulse + 0.999*_cumnoise

	player = yield addVehicle scene, controls, "res/viva/2006-VIVA-VT3-Sedan-SE.dae", caropts
	player.eye.add scene.camera
	player.physical.position.x = -1.75
	scene.player = player

	scene.player.speedometer = ui.gauge env,
		name: L "Speed"
		unit: L "km/h"
		value: ->
			speed = scene.player.getSpeed()*3.6
			Math.round speed

	engineSounds = yield DefaultEngineSound audioContext
	gainNode = audioContext.createGain()
	gainNode.connect audioContext.destination
	engineSounds.connect gainNode
	scene.afterPhysics.add ->
		rev = Math.abs(player.getSpeed())/(200/3.6)
		rev = Math.max 0.1, rev
		rev = (rev + 0.1)/1.1
		gain = scene.playerControls.throttle
		gain = (gain + 0.5)/1.5
		gainNode.gain.value = gain
		engineSounds.setPitch rev*2000
	scene.onStart.add engineSounds.start
	scene.onExit.add engineSounds.stop

	scene.onStart ->
		env.container.addClass "hide-cursor"
	scene.onExit ->
		env.container.removeClass "hide-cursor"

	scene.preroll = seqr.bind ->*
		# Tick a couple of frames for the physics to settle
		t = Date.now()
		n = 100
		for [0 to n]
			# Make sure the car can't move during the preroll.
			# Yes, it's a hack
			controls
				..throttle = 0
				..brake = 0
				..steering = 0

			scene.tick 1/60
		console.log "Prewarming FPS", (n/(Date.now() - t)*1000)
	return scene

export minimalScenario = seqr.bind (env) ->*
	scene = new Scene
	addGround scene
	#leader = yield addVehicle scene
	sky = yield P.resolve assets.addSky scene
	scene.preroll = ->
		# Tick a couple of frames for the physics to settle
		scene.tick 1/60
		n = 100
		t = Date.now()
		for [0 to n]
			scene.tick 1/60
		console.log "Prewarming FPS", (n/(Date.now() - t)*1000)
	@let \scene, scene
	yield @get \done

exportScenario \freeDriving, (env) ->*
	# Load the base scene
	scene = yield baseScene env

	# The scene would be customized here
	#addMirror scene, env
	#console.log scene.player.body.mirrors
	#addFakeMirror scene, env, 0, 4.5/180*Math.PI
	#addFakeMirror scene, env, 1, 12.5/180*Math.PI
	#addFakeMirror scene, env, 2, -12.5/180*Math.PI
	#scene.onRender.add (dt) ->
	#	scene.mirror.renderer = env.renderer		
	#	scene.mirror.render()
	env.controls.change (btn) ->
		if btn == "catch"
			env.vrcontrols.resetPose()
			#scene.player.eye.position.y = 1.23 - scene.camera.position.y
			#scene.player.eye.position.z = 0.15  - scene.camera.position.z
			#scene.player.eye.position.x = 0.52 - scene.camera.position.x
			#scene.player.eye.rotation.y = Math.PI - scene.camera.rotation.y
			#scene.camera.rotation.x = 0
			#scene.camera.rotation.z = 0
			#scene.camera.rotation.y = 0
			#scene.camera.position.x = 0
			#scene.camera.position.z = 0
			#scene.camera.position.y = 0
	# "Return" the scene to the caller, so they know
	# we are ready
	@let \scene, scene

	# Run until somebody says "done".
	yield @get \done

export basePedalScene = (env) ->
	if env.opts.forceSteering
		return baseScene env
	env = env with
		controls: NonSteeringControl env.controls
	return baseScene env

catchthething = require './catchthething.ls'
addReactionTest = seqr.bind (scene, env) ->*
	react = yield catchthething.React()
	screen = yield assets.SceneDisplay()

	screen.object.position.z = -0.3
	screen.object.scale.set 0.12, 0.12, 0.12
	screen.object.visible = false
	#screen.object.position.y = 2
	#screen.object.rotation.y = Math.PI
	scene.camera.add screen.object

	env.controls.change (btn, isOn) !->
		if btn == "catch" and isOn and screen.object.visible
			react.catch()
		else if btn == "blinder"
			screen.object.visible = isOn

	react.event (type) ->
		env.logger.write reactionGameEvent: type

	scene.onRender.add (dt) ->
		react.tick dt
		env.renderer.render react.scene, react.camera, screen.renderTarget, true
		#env.renderer.render react.scene, react.camera

	return react
require './node_modules/three/examples/js/Mirror.js'
addMirror = (scene, env) ->
	mirror = new THREE.Mirror(2.25, 2.08, { clipBias: -0.300, textureWidth: 1024, textureHeight: 1024 } )


	mirrorMesh = new THREE.Mesh do
		new THREE.PlaneBufferGeometry 2.00, 2.00
		mirror.material
	mirror.position.y = 0 #1.245
	mirror.position.x = 0.01
	mirror.position.z = -6.38

	#mirror.material.side = THREE.BackSide
	#mirror.rotation.y -= Math.PI
	scene.mirror = mirror
	#scene.player.body.add mirror
	scene.camera.add mirror

addFakeMirror = (scene, env, ind, y) ->
	geometry = scene.player.body.mirrors[ind].geometry
	scene.player.body.mirrors[ind].material.transparent = false
	geometry.computeBoundingBox()
	max = geometry.boundingBox.max
	min = geometry.boundingBox.min
	w = max.x - min.x
	h = max.y - min.y
	offset = new THREE.Vector2(0 - min.x, 0 - min.y)
	range = new THREE.Vector2(max.x - min.x, max.y - min.y)

	FOV = 30.0*(h/w)
	camera = new THREE.PerspectiveCamera FOV, w/h, 0.01, 450000
	scene.player.body.add camera
	camera.position.x = (max.x + min.x) / 2.0
	camera.position.y = (max.y + min.y) / 2.0
	camera.position.z = (max.z + min.z) / 2.0
	camera.rotation.set(0, y, 0)

	renderTarget = new THREE.WebGLRenderTarget( 256, 256, { format: THREE.RGBFormat } )

	scene.player.body.mirrors[ind].material = new THREE.MeshBasicMaterial( { map: renderTarget.texture } )
	
	faces = geometry.faces
	geometry.faceVertexUvs[0] = []
	for i from 0 til faces.length
		v1 = geometry.vertices[faces[i].a]
		v2 = geometry.vertices[faces[i].b]
		v3 = geometry.vertices[faces[i].c]
	
	
		uv0 = new THREE.Vector2( ( v1.x - min.x ) / range.x, ( v1.y  - min.y) / range.y)
		uv1 = new THREE.Vector2( ( v2.x - min.x ) / range.x, ( v2.y - min.y ) / range.y)
		uv2 = new THREE.Vector2( ( v3.x - min.x ) / range.x, ( v3.y - min.y) / range.y)
		
		geometry.faceVertexUvs[0].push([uv0, uv1, uv2])

	scene.player.body.mirrors[ind].material.needsUpdate = true
	scene.player.body.mirrors[ind].geometry.uvsNeedUpdate = true
	
	scene.onRender.add (dt) ->
		env.renderer.render(scene.visual, camera, renderTarget, true )
	
addSpeedometer = (scene, env) ->

	geometry = new THREE.ConeGeometry(0.001, 0.05, 32 )
	geometry.translate(0, 0.025, 0)
	material = new THREE.MeshPhongMaterial( {color: 0xff0000} )
	cone = new THREE.Mesh geometry, material
	cone.position.y = 0
	scene.player.body.tricycle.geometry.computeBoundingBox()
	max = scene.player.body.tricycle.geometry.boundingBox.max
	min = scene.player.body.tricycle.geometry.boundingBox.min
	w = max.x - min.x
	h = max.y - min.y

	cone.position.x = (max.x + min.x) / 2.0
	cone.position.y = (max.y + min.y) / 2.0
	cone.position.z = (max.z + min.z) / 2.0
	scene.player.body.tricycle.add cone

	#tex = THREE.ImageUtils.loadTexture 'res/viva/2006-VIVA-VT3-Sedan-SE/speedometer.png'
	#scene.player.body.tricycle.material = new THREE.MeshPhongMaterial( {color: 0xffffff, map: tex} )
	#scene.player.body.tricycle.material.needsUpdate = true

	cone.rotation.z = Math.PI
	scene.onTickHandled ->
		speed = scene.player.getSpeed()*3.6
		speed /= 180
		#speed = Math.min(speed, 1)
		cone.rotation.z = -Math.PI*0.75 + (speed * Math.PI)

		

addBlinder = (scene, env) ->
	mask = new THREE.Mesh do
		new THREE.PlaneGeometry 1, 1
		new THREE.MeshBasicMaterial color: 0x000000, side: THREE.DoubleSide

	mask.position.y = 1.23 - 0.07
	mask.position.x = 0.37 - 0.03
	mask.position.z = 0.75
	mask.rotation.x = -63.5/180*Math.PI
	mask.scale.set 0.35, 0.5, 0.5

	#mask.position.z = -0.3
	#mask.position.x = 0.03
	#mask.position.y = -0.03
	#scene.camera.add mask

	scene.player.body.add mask

	self =
		change: Signal!
		glances: 0

	self._showMask = showMask = ->
		return if mask.visible
		if scene.leader
			scene.leader.visual.visible = false
		mask.visible = true
		self.change.dispatch true
		env.logger.write blinder: true
	self._showMask()

	self._liftMask = ->
		mask.visible = false
		if scene.leader
			scene.leader.visual.visible = true
		self.glances += 1
		self.change.dispatch false
		env.logger.write blinder: false
		setTimeout showMask, 300

	return self


addBlinderTask = (scene, env) ->
	self = addBlinder(scene, env)

	ui.gauge env,
		name: env.L "Glances"
		unit: ""
		value: ->
			self.glances


	env.controls.change (btn, isOn) ->
		return if btn != 'blinder'
		return if isOn != true
		self._liftMask()

	return self

addForcedBlinderTask = (scene, env, {interval=2}={}) ->
	self = addBlinder(scene, env)

	id = setInterval self~_liftMask, interval*1000
	env.finally ->
		clearInterval id

	return self

exportScenario \runTheLight, (env) ->*
	@let \intro,
		title: env.L "Run the light"
		subtitle: env.L "(Just this once)"
		content: $ env.L "%runTheLight.intro"

	scene = yield basePedalScene env
	startLight = yield assets.TrafficLight()
	startLight.position.x = -4
	startLight.position.z = 6
	startLight.addTo scene

	@let \scene, scene
	yield @get \run

	scene.player.onCollision (e) ~>
		@let \done, passed: true, outro:
			title: env.L "Passed"
			content: env.L '%runTheLight.outro'

	return yield @get \done

collisionReason = ({L}, e) ->
	switch (e.body.objectClass)
	| 'traffic-light' => L "You ran the red light!"
	| 'stop-sign' => L "You ran the stop sign!"
	| otherwise => L "You crashed!"

failOnCollision = (env, scn, scene) ->
	scene.player.onCollision (e) ->
		reason = collisionReason env, e
		scn.let \done, passed: false, outro:
			title: env.L "Oops!"
			content: reason
		return false

exportScenario \laneDriving, (env) ->*
	# Load the base scene
	scene = yield baseScene env
	scene.viva = undefined
	addFakeMirror scene, env, 0, 4.5/180*Math.PI
	addFakeMirror scene, env, 1, 12.5/180*Math.PI
	addFakeMirror scene, env, 2, -12.5/180*Math.PI
	addSpeedometer scene, env
	scene.player.body.traverse (obj) ->
		return if not obj.geometry?
		obj.geometry = new THREE.BufferGeometry().fromGeometry(obj.geometry)

	env.controls.change (btn) ->
		if btn == "catch"
			env.vrcontrols.resetPose()
	trafficControls = new TargetSpeedController
	distances = [-150, -100, -70, 170, 300, 400]
	cars = []
	for i from 0 til 6
		car = scene.leader = yield addVehicle scene, trafficControls, "res/viva/NPCViva.dae"
		car.physical.position.x = -1.75
		car.physical.position.z = distances[i]
		cars.push car
	for i from 0 til 6
		car = scene.leader = yield addVehicle scene, trafficControls, "res/viva/NPCViva.dae"
		car.physical.position.x = 1.75
		car.physical.position.z = distances[i]
		car.physical.quaternion.setFromEuler(0, Math.PI ,0, 'XYZ')
		cars.push car


	speeds = [30, 20, 50, 100, 20, 120]*2
	shuffleArray speeds
	while speeds[*-1] == 0
		shuffleArray speeds
	speedDuration = 10

	sequence = for speed, i in speeds
		[(i+1)*speedDuration, speed/3.6]

	scene.afterPhysics.add (dt) ->
		if scene.time > sequence[0][0] and sequence.length > 1
			sequence := sequence.slice(1)
		trafficControls.target = sequence[0][1]
		trafficControls.tick scene.leader.getSpeed(), dt
		for car in cars
			if scene.player.physical.position.z - car.physical.position.z > 400
				car.physical.position.z += 700
			if car.physical.position.z - scene.player.physical.position.z > 400
				car.physical.position.z -= 700

	# "Return" the scene to the caller, so they know
	# we are ready
	@let \scene, scene

	# Run until somebody says "done".
	yield @get \done

exportScenario \closeTheGap, (env) ->*
	@let \intro,
		title: env.L "Close the gap"
		content: env.L '%closeTheGap.intro'

	scene = yield basePedalScene env
	leader = yield addVehicle scene
	leader.physical.position.x = scene.player.physical.position.x
	leader.physical.position.z = 100

	failOnCollision env, @, scene

	@let \scene, scene

	yield @get \run

	distanceToLeader = ->
		rawDist = scene.player.physical.position.distanceTo leader.physical.position
		return rawDist - scene.player.physical.boundingRadius - leader.physical.boundingRadius

	env.controls.change (btn, isOn) !~>
		return unless btn == 'catch' and isOn
		distance = distanceToLeader!
		distance += 1.47 # HACK!
		@let \done, passed: true, outro:
			title: env.L "Passed"
			content: env.L "%closeTheGap.outro", distance: distance
		return false

	return yield @get \done


exportScenario \throttleAndBrake, (env) ->*
	L = env.L
	@let \intro,
		title: L "Throttle and brake"
		content: L '%throttleAndBrake.intro'

	scene = yield basePedalScene env

	goalDistance = 200
	startLight = yield assets.TrafficLight()
	startLight.position.x = -4
	startLight.position.z = 6
	startLight.addTo scene

	stopSign = yield assets.StopSign!
		..position.x = -4
		..position.z = goalDistance + 10
		..addTo scene

	failOnCollision env, @, scene

	finishSign = yield assets.FinishSign!
	finishSign.position.z = goalDistance
	finishSign.addTo scene
	ui.gauge env,
		name: L "Time"
		unit: L "s"
		value: ->
			if not startTime?
				return 0.toFixed 2
			(scene.time - startTime).toFixed 2


	@let \scene, scene
	yield @get \run

	yield P.delay 2000
	yield startLight.switchToGreen()
	startTime = scene.time

	finishSign.bodyPassed(scene.player.physical).then ~> scene.onTickHandled ~>
		return if Math.abs(scene.player.getSpeed()) > 0.1
		time = scene.time - startTime
		@let \done, passed: true, outro:
			title: L "Passed"
			content: L '%throttleAndBrake.outro', time: time
		return false

	return yield @get \done

exportScenario \stayOnLane, (env) ->*
	L = env.L
	@let \intro,
		title: L "Stay on lane"
		content: L '%stayOnLane.intro'

	scene = yield baseScene env

	goalDistance = 200
	startLight = yield assets.TrafficLight()
	startLight.position.x = -4
	startLight.position.z = 6
	startLight.addTo scene

	stopSign = yield assets.StopSign!
		..position.x = -4
		..position.z = goalDistance + 10
		..addTo scene

	failOnCollision env, @, scene

	finishSign = yield assets.FinishSign!
	finishSign.position.z = goalDistance
	finishSign.addTo scene
	ui.gauge env,
		name: L "Time"
		unit: L "s"
		value: ->
			if not startTime?
				return 0.toFixed 2
			(scene.time - startTime).toFixed 2
	
	barrelPosition = 0.4
	barrel = yield assets.ConstructionBarrel!
	barrel.position.z = 50
	barrel.position.x = -barrelPosition
	barrel.addTo scene

	barrel = yield assets.ConstructionBarrel!
	barrel.position.z = 100
	barrel.position.x = barrelPosition - 7/2.0
	barrel.addTo scene

	barrel = yield assets.ConstructionBarrel!
	barrel.position.z = 150
	barrel.position.x = -barrelPosition
	barrel.addTo scene

	@let \scene, scene
	yield @get \run

	yield P.delay 2000
	yield startLight.switchToGreen()
	startTime = scene.time

	finishSign.bodyPassed(scene.player.physical).then ~> scene.onTickHandled ~>
		return if Math.abs(scene.player.getSpeed()) > 0.1
		time = scene.time - startTime
		@let \done, passed: true, outro:
			title: L "Passed"
			content: L '%stayOnLane.outro', time: time
		return false

	return yield @get \done

speedControl = exportScenario \speedControl, (env) ->*
	L = env.L
	@let \intro,
		title: L "Speed control"
		content: L "%speedControl.intro"

	scene = yield basePedalScene env
	limits = [
		[-Infinity, 50]
		[20, 50]
		[200, 30]
		[250, 80]
		[500, 60]
	]
	goalDistance = 700

	for [dist, limit] in limits
		sign = yield assets.SpeedSign limit
		sign.position.z = dist
		sign.position.x = -4
		scene.visual.add sign
	limits.reverse()
	currentLimit = ->
		mypos = scene.player.physical.position.z
		for [distance, limit] in limits
			break if distance < mypos

		return limit

	limitSign = ui.gauge env,
		name: L "Speed limit"
		unit: L "km/h"
		value: currentLimit

	illGainsMultiplier = 10
	illGains = 0
	timePenalty = 0
	scene.afterPhysics (dt) ->
		return if not startTime?
		limit = currentLimit!
		speed = Math.abs scene.player.getSpeed()*3.6
		if speed <= limit
			limitSign.normal()
			return

		limitSign.warning()
		traveled = (speed/3.6)*dt
		legalMinTime = traveled/(limit/3.6)
		timeGained = legalMinTime - dt

		illGains += timeGained
		timePenalty := illGains*illGainsMultiplier

	ui.gauge env,
		name: L "Penalty"
		unit: "s"
		value: ->
			timePenalty.toFixed 2

	startLight = yield assets.TrafficLight()
	startLight.position.x = -4
	startLight.position.z = 6
	startLight.addTo scene

	stopSign = yield assets.StopSign!
		..position.x = -4
		..position.z = goalDistance + 10
		..addTo scene

	failOnCollision env, @, scene

	scene.player.onCollision (e) ~>
		@let \done, passed: false, outro:
			title: L "Oops!"
			content: L "You ran the red light!"
		return false

	finishSign = yield assets.FinishSign!
	finishSign.position.z = goalDistance
	finishSign.addTo scene

	@let \scene, scene
	yield @get \run

	yield P.delay 1000
	yield startLight.switchToGreen()
	startTime = scene.time

	finishSign.bodyPassed(scene.player.physical).then ~> scene.onTickHandled ~>
		return if Math.abs(scene.player.getSpeed()) > 0.1

		time = scene.time - startTime
		@let \done, passed: true, outro:
			title: L "Passed"
			content: L '%speedControl.outro', time: time, timePenalty: timePenalty
		return false

	return yield @get \done

exportScenario \blindSpeedControl, (env) ->*
	L = env.L
	base = speedControl env

	intro = yield base.get \intro
	@let \intro,
		title: L "Anticipatory speed control"
		content: L '%blindSpeedControl.intro'

	scene = yield base.get \scene

	addBlinderTask scene, env
	@let \scene, scene

	yield @get \run
	base.let \run

	result = yield base.get \done

	@let \done, result

	return result


{IdmVehicle, LoopMicrosim} = require './microsim.ls'

class MicrosimWrapper
	(@phys) ->
	position:~->
		@phys.position.z
	velocity:~->
		@phys.velocity.z

	acceleration:~-> null

	step: ->

{knuthShuffle: shuffleArray} = require 'knuth-shuffle'

{TargetSpeedController} = require './controls.ls'
followInTraffic = exportScenario \followInTraffic, (env, {distance=2000}={}) ->*
	L = env.L
	@let \intro,
		title: L "Supermiler"
		content: $ L "%followInTraffic.intro"

	scene = yield basePedalScene env
	#addReactionTest scene, env
	#addBlinderTask scene, env

	startLight = yield assets.TrafficLight()
	startLight.position.x = -4
	startLight.position.z = 6
	startLight.addTo scene

	goalDistance = distance
	finishSign = yield assets.FinishSign!
	finishSign.position.z = goalDistance
	finishSign.addTo scene
	finishSign.visual.visible = false

	scene.player.onCollision (e) ~>
		reason = L "You crashed!"
		if e.body.objectClass == "traffic-light"
			reason = L "You ran the red light!"
		@let \done, passed: false, outro:
			title: L "Oops!"
			content: reason
		return false

	maximumFuelFlow = 200/60/1000
	constantConsumption = maximumFuelFlow*0.1
	draftingCoeff = (d) ->
		# Estimated from Mythbusters!
		Math.exp(0) - Math.exp(-(d + 5.6)*0.1)

	consumption =
		time: 0
		distance: 0
		instant: 0
		total: 0
		noDraftTotal: 0
		avgLitersPer100km: (consumption=@total) ->
			metersPerLiter = @distance/consumption
			1.0/metersPerLiter*1000*100
		instLitersPer100km: ->
			metersPerLiter = Math.abs(scene.player.getSpeed())/@instant
			1.0/metersPerLiter*1000*100

	scene.afterPhysics.add (dt) !->
		return if not startTime?
		consumption.time += dt
		consumption.distance += dt*Math.abs(scene.player.getSpeed())
		instant = env.controls.throttle*maximumFuelFlow + constantConsumption
		consumption.instant = instant * draftingCoeff(distanceToLeader!)
		consumption.total += consumption.instant*dt
		consumption.noDraftTotal += instant*dt

	ui.gauge env,
		name: L "Current consumption"
		unit: "l/100km"
		range: [0, 30]
		format: (v) ->
			if Math.abs(scene.player.getSpeed()) < 1.0
				return null
			return v.toFixed 2
		value: ->
			c = consumption.instLitersPer100km!
			return c

	ui.gauge env,
		name: L "Average consumption"
		unit: "l/100km"
		range: [0, 30]
		format: (v) ->
			return null if consumption.distance < 1
			return v.toFixed 2
		value: ->
			return consumption.avgLitersPer100km!

	/*nVehicles = 20
	spacePerVehicle = 20
	traffic = new LoopMicrosim nVehicles*spacePerVehicle
	for i in [1 til nVehicles]
		v = new IdmVehicle do
			a: 4.0
			b: 10.0
			timeHeadway: 1.0
		v.position = i*spacePerVehicle
		traffic.addVehicle v
	scene.beforePhysics.add traffic~step
	scene.traffic = traffic

	playerSim = new MicrosimWrapper scene.player.physical
	traffic.addVehicle playerSim

	leader = yield addVehicle scene
	leader.physical.position.z = playerSim.leader.position
	leader.physical.position.x = -1.75
	scene.beforeRender.add (dt) ->
		leader.forceModelSync()
		leader.physical.position.z = playerSim.leader.position
		leader.forceModelSync()*/

	leaderControls = new TargetSpeedController
	leader = scene.leader = yield addVehicle scene, leaderControls
	leader.physical.position.x = -1.75
	leader.physical.position.z = 10

	speeds = [0, 30, 40, 50, 60, 70, 80]*2
	shuffleArray speeds
	while speeds[*-1] == 0
		shuffleArray speeds
	speedDuration = 10

	sequence = for speed, i in speeds
		[(i+1)*speedDuration, speed/3.6]

	scene.afterPhysics.add (dt) ->
		if scene.time > sequence[0][0] and sequence.length > 1
			sequence := sequence.slice(1)
		leaderControls.target = sequence[0][1]
		leaderControls.tick leader.getSpeed(), dt

	headway =
		cumulative: 0
		time: 0
		average: ->
			@cumulative/@time
	cumHeadway = 0
	averageHeadway = 0
	scene.afterPhysics (dt) ->
		return if not startTime?
		headway.cumulative += dt*distanceToLeader!
		headway.time += dt


	distanceToLeader = ->
		rawDist = scene.player.physical.position.distanceTo leader.physical.position
		return rawDist - scene.player.physical.boundingRadius - leader.physical.boundingRadius

	scene.draftIndicator = ui.gauge env,
		name: L "Draft saving"
		unit: "%"
		#range: [0, 30]
		#format: (v) ->
		#	return null if consumption.distance < 1
		#	return v.toFixed 2
		value: ->
			c = draftingCoeff distanceToLeader!
			((1 - c)*100).toFixed 1

	# Wait for the traffic to queue up
	#while not traffic.isInStandstill()
	#	traffic.step 1/60

	finishSign.bodyPassed(scene.player.physical).then ~>
		@let \done, passed: true, outro:
			title: L "Passed!"
			content: L '%followInTraffic.outro', consumption: consumption
	@let \scene, scene
	yield @get \run
	yield P.delay 1000
	yield startLight.switchToGreen()
	startTime = scene.time

	return yield @get \done


exportScenario \blindFollowInTraffic, (env) ->*
	L = env.L
	base = followInTraffic env

	intro = yield base.get \intro
	@let \intro,
		title: L "Anticipating supermiler"
		content: L '%blindFollowInTraffic.intro'

	scene = yield base.get \scene
	scene.draftIndicator.el.hide()
	addBlinderTask scene, env
	@let \scene, scene

	yield @get \run
	base.let \run

	@get \done .then (result) ->
		base.let \done, result

	result = yield base.get \done

	@let \done, result

	return result

exportScenario \forcedBlindFollowInTraffic, (env, opts) ->*
	L = env.L
	base = followInTraffic env, distance: 1000

	intro = yield base.get \intro
	@let \intro,
		title: L "Distracted supermiler"
		content: L '%forcedBlindFollowInTraffic.intro'

	scene = yield base.get \scene
	scene.draftIndicator.el.hide()
	addForcedBlinderTask scene, env, opts
	@let \scene, scene

	yield @get \run
	base.let \run

	@get \done .then (result) ->
		base.let \done, result

	result = yield base.get \done

	@let \done, result

	return result

exportScenario \participantInformation, (env) ->*
	L = env.L
	currentYear = (new Date).getFullYear()
	radioSelect = (name, ...options) ->
		for {value, label} in options
			$ """
			<div class="radio">
				<label>
					<input type="radio" name="#name" value="#value">
					#label
				</label>
			</div>
			"""

	dialogs =
		->
			@ \title .text L "Welcome to the experiment"
			@ \text .append L "%intro.introduction"
			@ \accept .text L "Next"
			@ \cancel-button .hide!
		->
			@ \title .text L "Background information"
			@ \text .append L "%intro.backgroundInfo"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
		->
			@ \title .text L "Birth year"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			input = $("""<input name="birthyear" type="number" min="1900" max="#currentYear" style="color: black">""")
			.appendTo @ \inputs
			setTimeout input~focus, 0
		->
			@ \title .text L "Gender"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			@ \inputs .append radioSelect "gender",
				* value: 'female', label: L "Female"
				* value: 'male', label: L "Male"
		->
			@ \title .text L "Driving license year"
			@ \text .append L "%intro.license"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			input = $("""<input name="drivinglicenseyear" type="number" min="1900" max="#currentYear" style="color: black">""")
			.appendTo @ \inputs
			setTimeout input~focus, 0
		->
			@ \title .text L "Past year driving"
			@ \text .append L "On average, how frequently have you driven during the <strong>past year</strong>."
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			@ \inputs .append radioSelect "drivingFreqPastYear",
				* value: 'daily', label: L "Most days"
				* value: 'weekly', label: L "Most weeks"
				* value: 'monthly', label: L "Most months"
				* value: 'yearly', label: L "Few times a year"
				* value: 'none', label: L "Not at all"
		->
			@ \title .text L "Lifetime driving"
			@ \text .append L "On average, how frequently have you driven <strong>since you got your driver's license</strong>."
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			@ \inputs .append radioSelect "drivingFreqTotal",
				* value: 'daily', label: L "Most days"
				* value: 'weekly', label: L "Most weeks"
				* value: 'monthly', label: L "Most months"
				* value: 'yearly', label: L "Few times a year"
				* value: 'none', label: L "Not at all"
		->
			@ \title .text L "Past 12 month kilometrage"
			@ \text .append L "Give out an estimate on how many kilometres have you driven during the past 12 months."
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			@ \inputs .append radioSelect "drivingDist",
				* value: 'None', label: L "not driven"
				* value: '0', label: "<1000"
				* value: '1000', label: "1000 - 5000"
				* value: '5000', label: "5001 - 10 000"
				* value: '100000', label: "10 001 - 15 000"
				* value: '150000', label: "15 001 - 20 000"
				* value: '200000', label: "20 001 - 30 000"
				* value: '300000', label: "30 001 - 50 000"
				* value: '500000', label: "> 50 000"
		->
			@ \title .text L "Lifetime kilometrage"
			@ \text .append L "Give out an estimate on how many kilometres have you driven during your lifetime."
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			@ \inputs .append radioSelect "drivingDist",
				* value: '0', label: "<1000"
				* value: '1000', label: "1000 - 10 000"
				* value: '10000', label: "10 001 - 30 000"
				* value: '30000', label: "30 001 - 100 000"
				* value: '100000', label: "100 001 - 300 000"
				* value: '300000', label: "300 001 - 500 000"
				* value: '500000', label: "500 001 - 1 000 000"
				* value: '1000000', label: "> 1 000 000"
		->
			@ \title .text L "Video games"
			@ \text .append L "How frequently do you play video games?"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			@ \inputs .append radioSelect "gamingFreq",
				* value: 'daily', label: L "Most days"
				* value: 'weekly', label: L "Most weeks"
				* value: 'monthly', label: L "Most months"
				* value: 'yearly', label: L "Few times a year"
				* value: 'none', label: L "Not at all"
				* value: 'ex-player', label: L "I have played, but not anymore"
		->
			@ \title .text L "Driving games"
			@ \text .append L "How frequently do you play driving games? (e.g. Gran Turismo)"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			@ \inputs .append radioSelect "drivingGameFreq",
				* value: 'daily', label: L "Most days"
				* value: 'weekly', label: L "Most weeks"
				* value: 'monthly', label: L "Most months"
				* value: 'yearly', label: L "Few times a year"
				* value: 'none', label: L "Not at all"
				* value: 'ex-player', label: L "I have played, but not anymore"

	i = 0
	while i < dialogs.length
		result = yield ui.inputDialog env, dialogs[i]
		console.log result
		if result.canceled
			i -= 2
		i += 1

exportScenario \participantInformationBlindPursuit, (env) ->*
	L = env.L
	currentYear = (new Date).getFullYear()
	radioSelect = (name, ...options) ->
		for {value, label} in options
			$ """
			<div class="radio">
				<label>
					<input type="radio" name="#name" value="#value">
					#label
				</label>
			</div>
			"""

	dialogs =
		->
			@ \title .text L "Welcome to the experiment"
			@ \text .append L "%introBlindPursuit.introduction"
			@ \accept .text L "Next"
			@ \cancel-button .hide!
		->
			@ \title .text L "Participation is voluntary"
			@ \text .append L "%intro.participantRights"
			@ \cancel .text L "Previous"
			@ \accept .text L "I wish to participate"
		->
			@ \title .text L "Possible eye strain"
			@ \text .append L "%introBlindPursuit.eyeStrain"
			@ \cancel .text L "Previous"
			@ \accept .text L "OK"
		->
			@ \title .text L "Collection and use of data"
			@ \text .append L "%intro.dataUse"
			@ \cancel .text L "Previous"
			@ \accept .text L "I accept the usage of my data"
		->
			@ \title .text L "Background information"
			@ \text .append L "%intro.backgroundInfo"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
		->
			@ \title .text L "E-mail address"
			@ \text .append L "%intro.email"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			input = $('<input name="email" type="email" style="color: black">')
			.prop "placeholder", L "E-mail address"
			.appendTo @ \inputs
			setTimeout input~focus, 0
		->
			@ \title .text L "Birth year"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			input = $("""<input name="birthyear" type="number" min="1900" max="#currentYear" style="color: black">""")
			.appendTo @ \inputs
			setTimeout input~focus, 0
		->
			@ \title .text L "Gender"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			@ \inputs .append radioSelect "gender",
				* value: 'female', label: L "Female"
				* value: 'male', label: L "Male"

	i = 0
	while i < dialogs.length
		result = yield ui.inputDialog env, dialogs[i]
		console.log result
		if result.canceled
			i -= 2
		i += 1



exportScenario \experimentOutro, (env, cb=->) ->*
	L = env.L
	yield ui.instructionScreen env, (...args) ->
		@ \title .append L "The experiment is done!"
		@ \content .append L '%experimentOutro'
		@ \accept-button .hide()
		cb.apply @, [env].concat ...args


exportScenario \blindPursuitOld, (env, {nTrials=50, oddballRate=1}={}) ->*
	L = env.L
	@let \intro,
		title: L "Catch the ball"
		content: L '%blindPursuit.intro'

	scene = new Scene

	scene.preroll = ->
		# Tick a couple of frames for the physics to settle
		scene.tick 1/60
		n = 100
		t = Date.now()
		for [0 to n]
			scene.tick 1/60
		console.log "Prewarming FPS", (n/(Date.now() - t)*1000)


	screen = yield assets.SceneDisplay()

	screen.object.position.z = -0.1
	screen.object.scale.set 0.1, 0.1, 0.1
	screen.object.visible = true
	#screen.object.position.y = 2
	#screen.object.rotation.y = Math.PI
	scene.visual.add screen.object

	catcher = new catchthething.SpatialCatch oddballRate: oddballRate, controls: env.controls

	scene.onTickHandled ->
		objects = for obj in catcher.objects
			id: obj.id
			position: obj.mesh.position{x, y, z}
		env.logger.write do
			sceneTime: scene.time
			pursuitObjects: objects


	env.controls.change (btn, isOn) !->
		if btn == "catch" and isOn and screen.object.visible
			catcher.catch()


	scene.onRender.add (dt) ->
		catcher.tick dt
		env.renderer.render catcher.scene, catcher.camera, screen.renderTarget, true

	@let \scene, scene

	yield @get \run

	score =
		missed: 0
		catched: 0
		catchRate: ->
			@catched / @total!
		total: ->
			@catched + @missed

	catcher.objectAdded (obj) ->
		env.logger.write pursuitObjectAdded: obj.id
	catcher.objectCatched (obj) ->
		score.catched += 1
		env.logger.write pursuitObjectCatched: obj.id
	catcher.objectMissed (obj) ->
		score.missed += 1
		env.logger.write pursuitObjectMissed: obj.id


	catcher.objectHandled ~>
		return if score.total! < nTrials
		finalScore = (score.catchRate()*100).toFixed 1
		@let \done, passed: true, outro:
			title: env.L "Level passed"
			content: env.L "You caught #finalScore% of the balls"

	ui.gauge env,
		name: L "Catch percentage"
		unit: L '%'
		range: [0, 100]
		value: -> score.catchRate()*100
		format: (v) ->
			return v.toFixed 1

	result = yield @get \done

	return result

exportScenario \blindPursuitOld2, (env, {nRights=50, oddballRate=0.1}={}) ->*
	camera = new THREE.OrthographicCamera -1, 1, -1, 1, 0.1, 10
			..position.z = 5
	env.onSize (w, h) ->
		h = h/w
		w = 1
		camera.left = -w
		camera.right = w
		camera.bottom = -h
		camera.top = h
		camera.updateProjectionMatrix!

	scene = new Scene camera: camera

	#objectGeometry = new THREE.SphereGeometry 0.01, 32, 32
	#objectMaterial = new THREE.MeshBasicMaterial color: 0x00ff00
	#target = new THREE.Mesh objectGeometry, objectMaterial
	scene.visual.add new THREE.AmbientLight 0xffffff
	target = yield assets.ArrowMarker()
	target.position.set 0, 0, -1
	target.visible = true
	target.scale.set 0.08, 0.08, 0.08

	#target2 = new THREE.Mesh objectGeometry, objectMaterial
	#target2.position.set 0, 0, -0.05
	#target.add target2

	directions = ['up', 'down'] #, 'left', 'right']
	rotations =
		up: Math.PI
		left: -(Math.PI/2)
		right: (Math.PI/2)
		down: 0

	targetDirection = 'down'
	getCurrentDirection = ->
		dirs = {up, down, left, right} = env.controls{up, down, left, right}
		total = up + down + left + right
		if total == 0 or total > 1
			return void
		for name, value of dirs
			if value == 1
				return name

	scene.visual.add target
	scene.preroll = ->

	t = 0
	hideDuration = 0.2
	prevX = void
	hideTime = 0
	fadeDuration = 0.1
	fadeTime = 0

	score =
		right: 0
		wrong: 0
		total: -> (@right - @wrong)

	rightDirection = Signal()
	rightDirection -> score.right += 1
	wrongDirection = Signal()
	wrongDirection -> score.wrong += 1


	env.controls.change (key, isOn) ->
		return if not isOn
		if key == targetDirection
			rightDirection.dispatch()
		else
			wrongDirection.dispatch()

	rightDirection ->
		newdir = directions[Math.floor (Math.random()*directions.length)]
		targetDirection := newdir
		target.rotation.z = rotations[targetDirection]
		fadeTime := fadeDuration

	scene.beforeRender (dt) ~>
		#console.log score.total!
		reactionTime = t/nRights
		penaltyTime = (reactionTime * score.wrong)/nRights
		if score.total! >= nRights
			console.log score
			console.log t
			@let \done passed: true, score: score, time: t, outro:
				title: env.L "Round done!"
				content: env.L "Average correct reaction time was #{reactionTime.toFixed 3} seconds. You made #{score.wrong} errors, which cost about #{penaltyTime.toFixed 3} seconds."
			return false
		if score.right < 1
			return
		t += dt
		#target.position.x = (Math.cos t)*0.5
		cycleLength = 2
		pt = t + cycleLength / 2.0
		nthCycle = Math.floor(pt / cycleLength)
		cycleRatio = (pt % cycleLength) / cycleLength
		if nthCycle % 2 != 0
			cycleRatio = 1 - cycleRatio

		#if getCurrentDirection() == targetDirection
		#	# OMG!
		#	newdir = directions[Math.floor (Math.random()*directions.length)]
		#	targetDirection := newdir
		#	target.rotation.z = rotations[targetDirection]
		#	fadeTime := fadeDuration

		dist = 0.5
		target.position.x = x = (cycleRatio - 0.5)*2*dist
		if Math.sign(prevX) != Math.sign(x) and hideTime <= 0
			hideTime := hideDuration
			if Math.random() < oddballRate
				t += Math.sign(Math.random() - 0.5)*(hideDuration*0.5)
		prevX := x
		hideTime -= dt

		if fadeTime > 0
			#target.arrow.material.opacity = 1 - fadeTime/fadeDuration
			target.arrow.visible = false
		else
			#target.arrow.material.opacity = 1
			target.arrow.visible = true
		fadeTime -= dt

		target.visible = not (hideTime > 0)
		return

	@let \scene, scene
	yield @get \run

	return yield @get \done

exportScenario \blindPursuit, (env, {duration=60.0*3, oddballRate=0.1}={}) ->*
	@let \intro,
		title: env.L "Find the balance"
		content: env.L "Use the steering wheel to keep the ball as close to the scale center as you can."

	camera = new THREE.OrthographicCamera -1, 1, -1, 1, 0.1, 10
			..position.z = 5
	env.onSize (w, h) ->
		w = w/h
		h = 1
		camera.left = -w
		camera.right = w
		camera.bottom = -h
		camera.top = h
		camera.updateProjectionMatrix!

	scene = new Scene camera: camera

	assets.addMarkerScreen scene

	#objectGeometry = new THREE.SphereGeometry 0.01, 32, 32
	#objectMaterial = new THREE.MeshBasicMaterial color: 0x00ff00
	#target = new THREE.Mesh objectGeometry, objectMaterial
	scene.visual.add new THREE.AmbientLight 0xffffff
	target = yield assets.BallBoard()
	target.position.set 0, 0, -1
	target.visible = true
	target.scale.set 0.5, 0.5, 0.5

	#target2 = new THREE.Mesh objectGeometry, objectMaterial
	#target2.position.set 0, 0, -0.05
	#target.add target2
	scene.visual.add target
	scene.preroll = ->



	score =
		right: 0
		wrong: 0
		total: -> (@right - @wrong)



	env.controls.set autocenter: 0.3
	@let \scene, scene

	t = 0
	prevX = void

	yPosition = 0.0
	ySpeed = 0.0
	distance = 0
	acceleration = 0

	hideDuration = 0.3
	showDuration = 1.0
	prevHide = 0.0
	hideTime = 0

	cycleLength = 1.3
	timeManipulation = 0.5
	timeWarp = cycleLength / 2.0

	gravity = 5.0
	mass = 10.0
	weightedError = 1.0



	errorWave = env.audioContext.createOscillator()
	errorWave.frequency.value = 1000
	errorGain = env.audioContext.createGain()
	errorGain.gain.value = 0
	errorWave.connect errorGain
	#errorGain.connect env.audioContext.destination
	#errorWave.start()
	#scene.onExit.add -> errorWave.stop()

	#ui.gauge env,
	#	name: "Speed"
	#	value: -> ySpeed.toFixed 2

	/*engineSounds = yield DefaultEngineSound env.audioContext
	gainNode = env.audioContext.createGain()
	gainNode.connect env.audioContext.destination
	engineSounds.connect gainNode
	
	engineSounds.start()
	scene.onExit.add engineSounds.stop*/

	totalError = 0
	prevHideCycle = void

	scene.beforeRender (dt) !~>
		t += dt
		if t >= duration
			meanError = totalError/t
			relativeError = meanError/0.5
			totalScore = (1 - relativeError)*100
			@let \done passed: true, outro:
				title: env.L "Round done!"
				content: "Your score was #{totalScore.toFixed 1}%"
				totalScore: score
			return false

		angle = -env.controls.steering*Math.PI*0.3
		target.turnable.rotation.z = -angle

		angle += (Math.random() - 0.5)*Math.PI*0.1

		force = mass*(gravity*Math.sin(angle))
		acceleration = force/mass
		ySpeed += acceleration*dt
		yPosition += ySpeed*dt
		error = Math.abs yPosition

		totalError += dt*error

		relError = error/0.25

		if yPosition < -0.5 and ySpeed < 0
			yPosition := -0.5
			ySpeed := 0
		if yPosition > 0.5 and ySpeed > 0
			yPosition := 0.5
			ySpeed := 0

		target.ball.position.x = yPosition

		errorGain.gain.value = error

		pt = t + timeWarp
		nthCycle = Math.floor(pt / cycleLength)
		cycleRatio = (pt % cycleLength) / cycleLength
		if nthCycle % 2 != 0
			cycleRatio = 1 - cycleRatio

		dist = 0.5
		prevTargetPos = target.position.y
		#target.position.y = y = (cycleRatio - 0.5)*2*dist
		rotSpeed = 2.0
		target.position.y = (Math.sin pt*rotSpeed)*dist
		target.position.x = (Math.cos pt*rotSpeed)*dist
		if (t - prevHide) > showDuration
		#if Math.sign(prevTargetPos) != Math.sign(y) and prevHideCycle != nthCycle
			prevHideCycle := nthCycle
			prevHide := t
			hideTime := hideDuration
			if Math.random() < oddballRate
				coeff = (Math.random() - 0.5)*2
				timeWarp += coeff*timeManipulation
		hideTime -= dt

		target.visible = not (hideTime > 0)

		env.logger.write do
			balancingTask:
				time: t
				timeWarp: timeWarp
				ballPosition: target.ball.position{x, y, z}
				ballVelocity: ySpeed
				ballAcceleration: acceleration
				visualRotation: target.turnable.rotation.z
				trueRotation: angle
				targetPosition: target.position{x, y, z}
				targetVisible: target.visible

		/*rev = ySpeed / 5.0
		rev = Math.max 0.1, rev
		rev = (rev + 0.1)/1.1
		gain = 1 - damping
		gain = (gain + 0.5)/1.5
		gainNode.gain.value = gain
		engineSounds.setPitch rev*2000*/
	yield @get \run

	return yield @get \done


exportScenario \steeringCatcher, (env, {duration=60.0*3, oddballRate=0.1}={}) ->*
	@let \intro,
		title: env.L "Catch the blocks"
		content: env.L "Use the steering wheel to catch the blocks."

	camera = new THREE.OrthographicCamera -1, 1, -1, 1, 0.1, 10
			..position.z = 5
	width = 0.3
	height = 0.6
	margin = 0.0
	targetWidth = 0.05

	env.onSize (w, h) ->
		w = w/h
		h = 1
		camera.left = -w
		camera.right = w
		camera.bottom = -h
		camera.top = h
		camera.updateProjectionMatrix!

	scene = new Scene camera: camera
	scene.preroll = ->
	assets.addMarkerScreen scene

	#objectGeometry = new THREE.SphereGeometry 0.01, 32, 32
	#objectMaterial = new THREE.MeshBasicMaterial color: 0x00ff00
	#target = new THREE.Mesh objectGeometry, objectMaterial
	scene.visual.add new THREE.AmbientLight 0xffffff

	geo = new THREE.PlaneGeometry targetWidth, 0.01
	target = new THREE.Mesh geo, new THREE.MeshBasicMaterial color: 0xffffff, transparent: true
	target.position.y = -height
	scene.visual.add target

	geo = new THREE.SphereGeometry 0.01, 32, 32
	block = new THREE.Mesh geo, new THREE.MeshBasicMaterial color: 0xffffff
	block.position.y = height
	scene.visual.add block
	blockSpeed = 0.7
	speedup = 1.01
	slowdown = 1.03
	steeringSpeed = 2.0
	shineTime = 0.1

	hideDuration = 0.2
	showDuration = 1.0
	hideTime = 0
	prevHide = 0

	catched = 0
	missed = 0

	#env.controls = env.controls with steering: 0
	#env.container.mousemove (ev) ->
	#	x = ev.pageX/window.innerWidth
	#	x = (x - 0.5)*2.0
	#	env.controls.steering = -x

	bias = 0
	t = 0
	scene.beforeRender (dt) !~>
		t += dt
		if t >= duration
			totalScore = catched/(catched + missed)*100
			@let \done passed: true, outro:
				title: env.L "Round done!"
				content: "Your score was #{totalScore.toFixed 1}%"
				totalScore: totalScore
				finalSpeed: blockSpeed
			return false
		if block.position.y < -height
			if Math.abs(block.position.x) < targetWidth/2.0
				blockSpeed *= speedup
				target.shineLeft = shineTime
				catched += 1
			else
				blockSpeed /= slowdown
				missed += 1
			block.position.y = height
			bias := (Math.random() - 0.5)*2*(width - margin)
			env.logger.write steeringCatcherBias: bias

		block.position.y -= dt*blockSpeed
		#block.position.x += dt*env.controls.steering*blockSpeed*steeringSpeed
		block.position.x = env.controls.steering*3*width - bias
		#if block.position.x < -width
		#	block.position.x = -width
		#if block.position.x > width
		#	block.position.x = width

		if target.shineLeft > 0
			target.shineLeft -= dt
			target.material.opacity = 1
		else
			target.material.opacity = 0.5


		if (t - prevHide) > showDuration
			prevHide := t
			hideTime := hideDuration
			if Math.random() < oddballRate
				coeff = (Math.random() - 0.5)*2
				manipulation = (Math.random() - 0.5)*targetWidth*2
				env.logger.write steeringCatcherManipulation: manipulation
				bias += manipulation
		hideTime -= dt
		block.visible = not (hideTime > 0)

		env.logger.write do
			steeringCatcher:
				time: t
				ballPosition: block.position{x, y, z}
				ballVelocity: blockSpeed
				targetVisible: block.visible


	env.controls.set autocenter: 0.3
	@let \scene, scene
	yield @get \run

	return yield @get \done

shuffleArray = (a) ->
	i = a.length
	while (--i) > 0
		j = Math.floor (Math.random()*(i+1))
		[a[i], a[j]] = [a[j], a[i]]
	return a

exportScenario \pursuitDiscriminationPractice, (env) ->*
	minFrequency = 4
	maxFrequency = 32

	steps = [0.5, 0.3, 0.1, 0.05, 0.05, 0.05, 0.05, 0.05]
	progress = 0
	controller = (result={}) ->
		if result.correct
			progress += 1
		else
			progress -= 1
		progress := Math.max progress, 0
		if progress >= steps.length
			controller := staircase
			return controller result
		frequency: minFrequency
		targetDuration: steps[progress]

	stepUp = 1.05
	stepDown = 1.2
	currentFrequency = minFrequency
	trialsDone = 0
	reversalsNeeded = 10
	prevCorrect = true
	reversals = []
	staircase = (result) ->
		trialsDone += 1
		if prevCorrect != result.correct
			reversals.push currentFrequency
		if reversals.length >= reversalsNeeded
			return void
		prevCorrect := result.correct
		if result.correct
			currentFrequency := Math.min maxFrequency, currentFrequency*stepUp
		else
			currentFrequency := Math.max minFrequency, currentFrequency/stepDown

		frequency: currentFrequency

	base = pursuitDiscriminationBase env, (...args) -> return controller ...args

	@let \intro, yield base.get \intro
	@let \scene, yield base.get \scene
	yield @get \run ; base.let \run
	result = yield base.get \done
	@let \done
	result.estimatedFrequency = reversals.reduce((+))/reversals.length
	env.logger.write pursuitDiscriminationEstimatedFrequency: result.estimatedFrequency
	console.log "Estimated frequency", result.estimatedFrequency
	return result

exportScenario \pursuitDiscrimination, (env, {frequency=10}={}) ->*
	oddballs = [-0.1, 0.1, -0.25, 0.25, -0.4, 0.4]*2
	totalTrials = Math.round oddballs.length/0.2
	standards = [0.0]*(totalTrials - oddballs.length)
	sequence = shuffleArray standards.concat oddballs
	sequence = [].concat([0.0]*2, sequence, [0.0]*2)
	console.log "N trials", sequence.length
	base = pursuitDiscriminationBase env, ->
		if sequence.length == 0
			return void

		manipulation: sequence.pop()
		frequency: frequency

	@let \intro, yield base.get \intro
	@let \scene, yield base.get \scene
	yield @get \run ; base.let \run
	result = yield base.get \done
	@let \done, result
	return result

pursuitDiscriminationBase = seqr.bind (env, getParameters) ->*
	defaultParameters =
		speed: 1.3
		hideDuration: 0.3
		cueDuration: 2.0
		waitDuration: 2.0
		maskDuration: 0.3
		resultDuration: 2.0
		targetDuration: 0.05
		frequency: 10
		manipulation: 0
	parameters = defaultParameters with getParameters!

	gratingLeft = assets.SineGratingBitmap resolution: 256, cycles: parameters.frequency
	gratingRight = assets.SineGratingBitmap resolution: 256, cycles: parameters.frequency
	introContent = $ env.L '%pursuitDiscrimination.intro'
	gratingLeft = $(gratingLeft)
		.css width: '50%', height: 'auto', display: 'inline-block'
		.css transform: 'rotate(-45deg)'
	gratingRight = $(gratingRight)
		.css width: '50%', height: 'auto', display: 'inline-block'
		.css transform: 'rotate(45deg)'
	introContent.find '.leftStim' .append gratingLeft
	introContent.find '.rightStim' .append gratingRight
	@let \intro,
		title: env.L "Find the direction"
		content: introContent

	camera = new THREE.OrthographicCamera -1, 1, -1, 1, 0.1, 10
			..position.z = 5
	env.onSize (w, h) ->
		w = w/h
		h = 1
		camera.left = -w
		camera.right = w
		camera.bottom = -h
		camera.top = h
		camera.updateProjectionMatrix!

	scene = new Scene camera: camera
	scene.preroll = ->
	assets.addMarkerScreen scene

	scene.visual.add new THREE.AmbientLight 0xffffff

	platform = new THREE.Object3D()
	scene.visual.add platform

	target = yield assets.ArrowMarker()
	target.setFrequency 10
	target.scale.set 0.3, 0.3, 0.3
	target.signs.target.scale.set 0.3, 0.3, 0.3
	platform.add target
	@let \scene, scene

	t = 0

	score =
		correct: 0
		incorrect: 0
		percentage: -> @correct/(@correct + @incorrect)*100
		total:~ -> @correct + @incorrect

	oddballScore = score with
		correct: 0
		incorrect: 0

	pureScore = score with
		correct:~ -> score.correct - oddballScore.correct
		incorrect:~ -> score.incorrect - oddballScore.incorrect

	events =
		begin: Signal!
		hide: Signal!
		show: Signal!
		mask: Signal!
		query: Signal!
		wait: Signal!
		result: Signal!
		exit: Signal!

	for let name, signal of events
		signal !->
			env.logger.write pursuitDiscriminationState:
				name: name
				st: t


	schedule = (seconds, func) ->
		t = 0
		scene.beforeRender (dt) !->
			if t >= seconds
				func()
				return false
			t += dt

	trialResult = void

	events.begin !->
		trialResult := {}

		target.setFrequency parameters.frequency
		target.setSign 'cue'
		schedule parameters.cueDuration, events.hide~dispatch
	events.hide !->
		platform.visible = false
		schedule parameters.hideDuration, events.show~dispatch
	events.show !->
		target.signs.target.rotation.z = Math.sign(Math.random() - 0.5)*Math.PI/4.0
		platform.visible = true
		target.setSign 'target'
		schedule parameters.targetDuration, events.mask~dispatch
		env.controls.change (key, isOn) !->
			return if not isOn
			keys = ['left', 'right']
			return if key not in keys

			targetKey = keys[(target.signs.target.rotation.z < 0)*1]
			trialResult.correct = key == targetKey
			trialResult.targetKey = targetKey
			trialResult.pressedKey = key

			if trialResult.correct
				score.correct += 1
			else
				score.incorrect += 1

			if parameters.manipulation != 0
				if trialResult.correct
					oddballScore.correct += 1
				else
					oddballScore.incorrect += 1

			env.logger.write pursuitDiscriminationSummary:
				time: t
				parameters: parameters
				result: trialResult

			schedule 0, events.wait~dispatch
			return false
	events.mask !->
		return if trialResult.correct?
		target.setSign 'mask'
		schedule parameters.maskDuration, events.query~dispatch
	events.query !->
		return if trialResult.correct?
		target.setSign 'query'
	events.wait !->
		target.setSign 'wait'
		schedule parameters.waitDuration, events.result~dispatch

	events.result !->
		console.log parameters.manipulation, pureScore.percentage!, oddballScore.percentage!

		target.setSign if trialResult.correct then 'success' else 'failure'

		params = getParameters trialResult
		if not params?
			schedule parameters.resultDuration, events.exit~dispatch()
			return
		parameters := defaultParameters with params

		schedule parameters.resultDuration, events.begin~dispatch


	events.exit !~>
		@let \done, score: score, outro:
			title: env.L "Round done!"
			content: env.L "You got #{score.percentage!.toFixed 1}% right!"

	displacement = 1.0
	movementDirection = -1
	events.begin ->
		movementDirection *= -1
		platform.position.x = (-movementDirection)*displacement
		timeToCenter = displacement/parameters.speed
		startTime = (parameters.cueDuration + parameters.hideDuration) - timeToCenter
		hintTime = Math.max(0, startTime - 0.3)
		target.signs.cue.material.opacity = 0.5
		target.signs.cue.material.needsUpdate = true
		schedule hintTime, ->
			target.signs.cue.material.opacity = 1.0
			target.signs.cue.material.needsUpdate = true
		schedule startTime, -> scene.beforeRender (dt) !->
			platform.position.x += dt*movementDirection*parameters.speed
			if platform.position.x*movementDirection >= displacement
				platform.position.x = movementDirection*displacement
				return false
	events.hide ->
		#manipulation := manipulationSequence.pop() ? 0
		platform.position.x += movementDirection*parameters.manipulation*parameters.speed

	events.begin.dispatch()
	scene.afterRender (dt) !->
		env.logger.write pursuitDiscrimination:
			platformPosition: platform.position{x,y,z}
			targetRotation: target.signs.target.rotation.z
	scene.afterRender (dt) !-> t += dt

	yield @get \run
	return yield @get \done

exportScenario \steerToTarget, (env, {duration=60.0, oddballRate=0.05}={}) ->*
	camera = new THREE.OrthographicCamera -1, 1, -1, 1, 0.1, 10
			..position.z = 5

	targetSize = 0.03
	targetDuration = 1.0
	circleRadius = 0.1
	cricleLength = circleRadius*2*Math.PI
	angleSpan = (2*targetSize)/circleRadius
	targetRange = 0.4
	rotSpeed = 2.0
	rotRadius = 0.3

	hideDuration = 0.3
	showDuration = 1.0
	prevHide = 0.0
	hideTime = 0

	cycleLength = 1.3
	timeManipulation = 0.5
	timeWarp = cycleLength / 2.0


	env.onSize (w, h) ->
		w = w/h
		h = 1
		camera.left = -w
		camera.right = w
		camera.bottom = -h
		camera.top = h
		camera.updateProjectionMatrix!

	scene = new Scene camera: camera
	scene.preroll = ->
	assets.addMarkerScreen scene

	scene.visual.add new THREE.AmbientLight 0xffffff

	platform = new THREE.Object3D()
	scene.visual.add platform

	geo = new THREE.SphereGeometry targetSize, 32, 32
	#geo = new THREE.PlaneGeometry 0.01, circleRadius
	pointer = new THREE.Mesh geo, new THREE.MeshBasicMaterial color: 0xffffff, transparent: true, opacity: 0.5
	#target.position.y = -height
	pointer.position.z = 0.1
	#platform.add pointer

	geo = new THREE.SphereGeometry targetSize/2.0, 32, 32
	target = new THREE.Mesh geo, new THREE.MeshBasicMaterial color: 0xffffff, transparent: true, opacity: 0.5
	platform.add target

	horizon = new THREE.Mesh do
			new THREE.PlaneGeometry targetRange*2, 0.01
			new THREE.MeshBasicMaterial color: 0xffffff, transparent: true, opacity: 0.5

	#platform.add horizon

	targetTimeLeft = 0.0
	slowdown = 1.03
	speedup = 1.01
	targetAngle = targetRange/2.0

	#env.controls.change (btn, isOn) !->
	#	return if not (btn == "blinder" and isOn)
	#	error = target.position.distanceTo pointer.position
	#
	#	if error < targetSize
	#		targetAngle := -targetAngle
	#		if Math.random() < oddballRate
	#			manipulation := (Math.random() - 0.5)*manipulationRange
	#		else
	#			manipulation := 0
	#		#targetAngle := (Math.random() - 0.5)*targetRange

	#env.controls = env.controls with steering: 0
	#env.container.mousemove (ev) ->
	#	x = ev.pageX/window.innerWidth
	#	x = (x - 0.5)*2.0
	#	env.controls.steering = -x


	rotToAngle = (obj, angle) ->
		obj.position.x = Math.sin(angle)*circleRadius
		#obj.position.y = Math.cos(angle)*circleRadius
	t = 0
	scene.beforeRender (dt) !->
		t += dt
		pt = t + timeWarp
		period = 1/2.0
		platform.position.x = Math.cos(pt/period)*rotRadius
		platform.position.y = Math.sin(pt/period)*rotRadius
		#target.position.y = (Math.sin pt*rotSpeed)*rotRadius
		#target.position.x = (Math.cos pt*rotSpeed)*rotRadius
		#target.position.x = env.controls.steering*circleRadius
		#pointer.position.x = env.controls.steering

		#pointerAngle = env.controls.steering*(Math.PI*3)
		#rotToAngle pointer, -pointerAngle
		#rampInTime = 60
		#w = Math.min 0.5, t/rampInTime
		#targetAngle := Math.sin(t*2)*targetRange#*(1 - w) + w*Math.sin(t*4)*targetRange
		#rotToAngle target, targetAngle
		targetPeriod = 0.5
		#target.position.x = Math.sin((t + timeWarp)/targetPeriod)*targetRange

		if (t - prevHide) > showDuration
		#if Math.sign(prevTargetPos) != Math.sign(y) and prevHideCycle != nthCycle
			prevHide := t
			hideTime := hideDuration
			if Math.random() < oddballRate
				coeff = (Math.random() - 0.5)*2
				timeWarp += coeff*timeManipulation
				#platform.position.y = coeff*0.1
		hideTime -= dt

		platform.visible = not (hideTime > 0)

		#targetTimeLeft -= dt
		#if targetTimeLeft <= 0
		#	targetAngle = (Math.random() - 0.5)*targetRange
		#	target.rotation.z = targetAngle
		#	targetTimeLeft := targetDuration
		#angleError = pointer.rotation.z - target.rotation.z
		#if Math.abs(angleError) < angleSpan/2
		#	rawTarget.material.opacity = 0.75
		#else
		#	rawTarget.material.opacity = 0.5

	env.controls.set autocenter: 0.0
	@let \scene, scene
	yield @get \run

	return yield @get \done

exportScenario \vsyncTest, (env) ->*
	camera = new THREE.OrthographicCamera -1, 1, -1, 1, 0.1, 10
			..position.z = 5

	env.onSize (w, h) ->
		w = w/h
		h = 1
		camera.left = -w
		camera.right = w
		camera.bottom = -h
		camera.top = h
		camera.updateProjectionMatrix!

	scene = new Scene camera: camera
	scene.preroll = ->

	geo = new THREE.SphereGeometry 0.3, 32, 32
	cyan = new THREE.Mesh geo, new THREE.MeshBasicMaterial color: 0x00ffff
	red = new THREE.Mesh geo, new THREE.MeshBasicMaterial color: 0xff0000

	scene.visual.add cyan
	scene.visual.add red

	i = 0
	scene.beforeRender (dt) !->
		i += 1
		if i%2 == 0
			cyan.visible = true
			red.visible = false
		else
			cyan.visible = false
			red.visible = true


	@let \scene, scene
	yield @get \run

	return yield @get \done



exportScenario \soundSpook, (env, {preIntro=false, spookRate=1/20.0 duration=90.0, preSilence=30.0, postSilence=20.0}={}) ->*
	bell = yield BellPlayer env
	noise = yield NoisePlayer env

	nBursts = Math.round duration*spookRate
	times = for i from 0 to nBursts
		Math.random()*duration
	times = prelude.sort times
	schedule = [times[0]]
	for i from 1 til times.length
		schedule.push times[i] - times[i - 1]

	if preIntro
		yield ui.instructionScreen env, ->
			@ \title .append env.L "Relaxation and sound response"
			@ \subtitle .append env.L "Notification sound"
			@ \content .append env.L "%soundSpook.notificationSound"
			@ \accept .text env.L "Play the notification sound"
		yield bell()


		yield ui.instructionScreen env, ->
			@ \title .append env.L "Relaxation and sound response"
			@ \subtitle .append env.L "Noise sound"
			@ \content .append env.L '%soundSpook.noiseSound'
			"""
			During the relaxation periods, a noise sound is occasionally played.
			This is used to measure how your nervous system responses to sudden events.
			Please try not to move when you hear the sound even if you get surprised,
			and keep your eyes closed.
			"""
			@ \accept .text env.L "Play the noise sound"
		yield noise()

	yield ui.instructionScreen env, ->
			@ \title .append env.L "Relaxation and sound response"
			@ \content .append env.L '%soundSpook.instruction'

	msg = $('<h1>')
		.text env.L "Please keep your eyes closed"
		.css do
			"text-align": "center"
			"margin-top": "10%"
	env.container.append msg
	yield bell()

	env.logger.write soundSpookEvent: "preSilenceStart"
	yield ui.sleep preSilence
	env.logger.write soundSpookEvent: "preSilenceDone"
	for pause in schedule
		yield ui.sleep pause
		env.logger.write soundSpookEvent: "noiseBurst"
		noise()


	env.logger.write soundSpookEvent: "postSilenceStart"
	yield ui.sleep postSilence
	env.logger.write soundSpookEvent: "postSilenceDone"
	yield bell()
