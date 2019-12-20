P = require 'bluebird'
Co = P.coroutine
$ = require 'jquery'
seqr = require './seqr.ls'

{addGround, Scene} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{NonSteeringControl, NonThrottleControl} = require './controls.ls'
{circleScene} = require './circleScene.ls'
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

	player = yield addVehicle scene, controls, caropts
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

exportScenario \laneDriving, (env) ->*
	# Load the base scene
	scene = yield baseScene env
	MT = new Multithread(5)
	car = MT.process(addVehicle)
	trafficControls = new TargetSpeedController
	distances = [15, 70, 170, 300, 400]
	cars = []
	for i from 0 til 5
		car = scene.leader = yield MT.process(scene, trafficControls)
		car.physical.position.x = -1.75
		car.physical.position.z = 10 + distances[i]
		cars.push car
	for i from 0 til 3
		car = scene.leader = yield addVehicle scene, trafficControls
		car.physical.position.x = 1.75
		car.physical.position.z = 10 + distances[i]
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

probeOrder = (scene, n) ->
	array = []
	for i from 0 til n
		for j from 1 til 13
			if j % 2 == 0
				if j % 4 == 0 && scene.params.four == true
					array.push([i, 2])
				else
					array.push([i, 0])
			else
				if j % 3 == 0 && scene.params.four == true
					array.push([i, 3])
				else
					array.push([i, 1])
	counter = n*8
	i = array.length
	while (--i) > 0
		j = Math.floor (Math.random()*(i+1))
		[array[i], array[j]] = [array[j], array[i]]
	array.reverse()
	array.push([0,0])
	scene.order = array

transientScreen = (scene) ->
	for i from 0 til scene.probes.length
		if scene.probes[i].stim[1].visible == true
			scene.probes[i].stim[1].visible = false
			scene.probes[i].current = 0
		scene.transientScreen = false
		scene.targetScreen = false

clearProbes = (scene) ->
	for i from 0 til scene.probes.length
		scene.probes[i].current = 0
		for j from 1 til 7
			scene.probes[i].stim[j].visible = false
		scene.targetScreen = false
		scene.transientScreen = false

colorProbes = (scene) ->
	mat1 = new THREE.MeshBasicMaterial color: 0x0000FF, transparent: true, depthTest: false, depthWrite: false
	mat2 = new THREE.MeshBasicMaterial color: 0xDC143C, transparent: true, depthTest: false, depthWrite: false
	for i from 0 til scene.probes.length
		scene.probes[i].pA.material = mat1
		scene.probes[i].p4.material = mat2
		if scene.params.deviant == 1
				scene.probes[i].pA.material = mat2
				scene.probes[i].p4.material = mat1

addProbes = (scene, savedSeed) ->

	curr = [0,0,0,0,0]
	used = []
	for i from 0 til scene.probes.length
		scene.probes[i].stim[7].visible = false
		seed = Math.floor((Math.random() * (4 - 1)) + 2)
		used.push seed
		scene.probes[i].stim[seed].visible = true
		scene.probes[i].current = seed
		curr[i] = seed


	probe = Math.floor((Math.random() * 4))
	if savedSeed == undefined
		seed = Math.random()
	else
		seed = savedSeed
	chance = 0.5
	if seed >= chance
		for i from 1 til 7
			scene.probes[probe].stim[i].visible = false
		scene.probes[probe].stim[1].visible = true
		scene.probes[probe].current = 1
		scene.targetPresent = true
		scene.target = probe
		curr[probe] = 1
	else
		scene.targetPresent = false

	for i from 0 til scene.probes.length
		if curr[i]==scene.prev[i]
			clearProbes scene
			addProbes scene, seed
			return
	scene.prev = curr
	scene.targetScreen = true
	scene.transientScreen = false

transientTransistion = (scene) ->
	if (scene.time - scene.dT) >= 1 && scene.targetScreen == true && scene.transientScreen == false
		transientScreen scene
	if (scene.time - scene.dT) >= 2.25 && scene.transientScreen == false
		transientScreen scene

dif = (scene) ->
	dir = scene.params.direction
	pos = scene.player.pos
	roadSecond = scene.roadSecond
	futPos = scene.futPos
	if (pos - futPos >= 0 ||(1+pos) - futPos >= 0 && (1+pos) - futPos < roadSecond) && dir==1 || (futPos - pos >= 0 || (futPos+1) - pos >= 0 && (futPos+1) - pos < roadSecond) && dir==-1
		return true
	else
		return false

futPos = (scene) ->
		dir = scene.params.direction
		roadSecond = scene.roadSecond
		seed = Math.random()

		updateTime = scene.params.updateTime
		scene.futPos += roadSecond*updateTime

		if scene.futPos > 1 || scene.futPos < 0
			scene.futPos -= dir


probeLogic = (scene) ->
	roadPosition scene
	if scene.time - scene.dT > scene.visibTime
		clearProbes scene
	if dif(scene)==true
		clearProbes scene
		scene.reacted = false
		if scene.probeIndx == scene.params.duration
			scene.end = true
		else
			if scene.reacted == false
				if scene.targetPresent == true
					scene.scoring.missed += 1
					scene.probes[scene.target].missed += 1
			addProbes scene
			if scene.targetPresent
					scene.scoring.maxScore += 1
			i = scene.probeIndx
			scene.probeIndx += 1
			futPos scene
		scene.dT = scene.time

fixLogic = (env, scene, sound, s) ->
	dist = 2
	if scene.time - scene.dT > 0.4 && scene.fixcircles[scene.probeIndx + dist].position.y > -0.1
		for i from 0 til 2
			scene.fixcircles[scene.probeIndx + dist + i].position.y = -100
			if i == 0 && scene.switcheroo
				pos = scene.fixcircles[scene.probeIndx + dist + i].position.x
				scene.fixcircles[scene.probeIndx + dist + i].position.x = scene.startX + Math.abs(scene.startX - pos)*Math.sign(scene.startX - pos)
			env.logger.write do
				probeIndex: scene.probeIndx + dist + i
				preview: false
		
	if dif(scene)==true
		if scene.probeIndx == scene.params.duration
			scene.end = true
		else
			scene.probeIndx += 1
			scene.adjInd += 1
			currPos = scene.futPos
			futPos scene
			calculateFuture scene, 1, s/3.6, currPos
			env.logger.write futPos: scene.centerLine.getPointAt(scene.futPos)
		scene.dT = scene.time
		n = scene.params.targets
		s = Math.random()



		if s > 2
			scene.switcheroo = true
		else
			scene.switcheroo = false

		scene.fixcircles[scene.probeIndx].position.y = -0.08
		if scene.fixcircles[scene.probeIndx + dist].turn_wp == true
			preview = scene.params.previews[0]
			scene.params.previews.shift()
			console.log preview, scene.params.previews
			if preview
				for i from 0 til 2
					scene.fixcircles[scene.probeIndx + dist + i].position.y = -0.08
					if i == 0 && scene.switcheroo
						pos = scene.fixcircles[scene.probeIndx + dist + i].position.x
						scene.fixcircles[scene.probeIndx + dist + i].position.x = scene.startX + Math.abs(scene.startX - pos)*Math.sign(scene.startX - pos)
					env.logger.write do
						probeIndex: scene.probeIndx + dist + i
						preview: true
						switcheroo: scene.switcheroo


		env.logger.write do
			probePos: scene.fixcircles[scene.probeIndx].position
			roadPosition: scene.centerLine.getPointAt(scene.futPos)
			identity: scene.probeIndx
	n = scene.params.targets





triangle = (s) ->
	triA = new THREE.Shape()
	triA.moveTo(0,0)
	triA.lineTo(0, s)
	triA.lineTo(s, 0.5*s)
	triA.lineTo(0, 0 )
	triB = new THREE.Shape()
	triB.moveTo(s,s)
	triB.lineTo(s, 0)
	triB.lineTo(0, 0.5*s)
	triB.lineTo(s, s)
	return [triA, triB]

hexagon = (s) ->
	r = s/(2*Math.sin(Math.PI/6))
	h = Math.sin(60*Math.PI/180)*s
	x = -r*0.5
	y = -h
	hex = new THREE.Shape()
	hex.moveTo(s, y)
	for i from 0 til 360 by 60
		angle = i * Math.PI/180
		x += Math.cos(angle)*s
		y += Math.sin(angle)*s
		hex.lineTo(x, y)
	hex.lineTo(s, y)
	return hex


createTargetMesh = (scene, rotate, s) ->
	vFOV = scene.camera.fov
	angle = (vFOV/2) * Math.PI/180
	ratio = 1/vFOV
	params = {size: s, height: 0, font: "digital-7"}
	geo = new THREE.TextGeometry("E", params)

	material = new THREE.MeshBasicMaterial color: 0x000000, transparent: true, depthTest: false, depthWrite: false
	target = new THREE.Mesh geo, material
	r = s/(2*Math.sin(Math.PI/6))
	h = Math.sin(60*Math.PI/180)*s
	#rot = 30 * Math.PI/180
	#target.rotateZ(90 * Math.PI/180)

	geo.computeBoundingBox()
	offX = (geo.boundingBox.max.x - geo.boundingBox.min.x) / 2
	offY = (geo.boundingBox.max.y - geo.boundingBox.min.y) / 2
	target.position.x = -offX
	target.position.y = -offY

	return target



addProbe = (scene) ->
	vFOV = scene.camera.fov
	aspect = screen.width / screen.height
	hFOV = aspect * vFOV
	angle = (vFOV/2) * Math.PI/180
	ratio = 1/vFOV
	heigth = (Math.tan(angle) * 1000 * 2) * ratio
	s = heigth*1.25

	geo = new THREE.PlaneGeometry(s*2, s*2, 32)

	mat = new THREE.MeshBasicMaterial color: 0xFFFFFF, depthTest: false, depthWrite: false

	noise = THREE.ImageUtils.loadTexture 'res/world/noise.png'
	noise = new THREE.MeshBasicMaterial map:noise, transparent: true, depthTest: false, depthWrite: false


	probe = new THREE.Object3D()
	plane = new THREE.Mesh geo, mat

	target = createTargetMesh scene, 30, s

	p0 = new THREE.Object3D()
	p0.add plane
	p0.add target
	p0.rotateZ(45 * Math.PI/180)

	p60 = p0.clone()
	p120 = p0.clone()
	p180 = p0.clone()
	p240 = p0.clone()
	p300 = p0.clone()
	p360 = p0.clone()

	plane.rotateZ(45 * Math.PI/180)

	pNoise = new THREE.Mesh geo, noise

	i = -1
	probe.stim = [plane, p60, p120, p180, p240, p300, p360, pNoise]
	for p in probe.stim
		p.visible = false
		probe.add p
		p.rotateZ(i*90 * Math.PI/180)
		i += 1
	probe.stim[0].visible = true
	#probe.stim[1].visible = true

	probe.heigth = heigth
	probe.ratio = ratio

	probe.position.y = -1000
	probe.position.z = -1000

	scene.camera.add probe

	return probe

createProbes = (scene, n) ->
	scene.probes = []
	x = scene.player.physical.position.x
	z = scene.player.physical.position.z
	pos = []
	used = []
	for i from 0 til n
		probe = addProbe(scene)
		seed = Math.floor((Math.random() * (6 - 1)) + 2)
		while seed in used
			seed = Math.floor((Math.random() * (6 - 1)) + 2)
		used.push seed
		probe.current = 0
		#probe.stim[seed].visible = true
		probe.score = 0
		probe.missed = 0
		scene.probes.push(probe)

objectLoc = (object, x, y, scene) ->

	object.position.x = y
	object.position.y = -0.08
	object.position.z = x

	#console.log scene.camera.matrixWorld
	#console.log scene.camera.matrixWorld



	#console.log x, y

rotateObjects = (scene) ->
	scene.fixcircles[0].children[0].rotation.setFromRotationMatrix(scene.camera.matrixWorld, 'XYZ')
	scene.fixcircles[1].children[0].rotation.setFromRotationMatrix(scene.camera.matrixWorld, 'XYZ')
	scene.fixcircles[2].children[0].rotation.setFromRotationMatrix(scene.camera.matrixWorld, 'XYZ')
	scene.fixcircles[3].children[0].rotation.setFromRotationMatrix(scene.camera.matrixWorld, 'XYZ')

handleFixLocs = (scene, i = 0) ->
	p500 = scene.predict[0]
	p1000 = scene.predict[1]
	p2000 = scene.predict[2]
	p4000 = scene.predict[3]


	objectLoc scene.fixcircles[i], p500.x, p500.y, scene
	#objectLoc scene.fixcircles[1],  p1000.x, p1000.y
	#objectLoc scene.fixcircles[2],  p2000.x, p2000.y
	#objectLoc scene.fixcircles[3],  p4000.x, p4000.y



search = (scene) ->
	speed = scene.player.getSpeed()
	d = 0.01 / scene.centerLine.getLength()
	minC = 1000
	maxDist = speed*2/scene.centerLine.getLength()
	minPos = 0
	z = scene.player.physical.position.z
	x = scene.player.physical.position.x
	t = true
	
	s = 0
	e = 1

	if scene.player.minDist > 5 && scene.time - scene.lastSlowSearch > 0.2
		#console.log "slow search"
		scene.lastSlowSearch = scene.time
		s = -5
		e = 5
		d = 0.05 / scene.centerLine.getLength()

	for i from s til e
		l = Math.max (scene.player.pos + (i - 1)*(1/40.0)), 0
		r = Math.min (scene.player.pos + (i + 1)*(1/40.0)), 1
		l = Math.min l, 1
		r = Math.max r, 0
		while t == true
			if Math.abs(r - l) <= d
				pos = ((l + r) / 2)
				point = scene.centerLine.getPointAt(pos)
				c = ((z - point.x) ^ 2 + (x - point.y) ^ 2 ) ^ 0.5
				if c <= minC
					minC = c
					minPos = pos
				break
			lT = l + (r - l)/3
			rT =  r - (r - l)/3
			posLT = lT
			posRT = rT
			point = scene.centerLine.getPointAt(posLT)
			cLT = ((z - point.x) ^ 2 + (x - point.y) ^ 2 ) ^ 0.5

			point = scene.centerLine.getPointAt(posRT)
			cRT = ((z - point.x) ^ 2 + (x - point.y) ^ 2 ) ^ 0.5
			if cLT >= cRT
				l = lT
			else
				r = rT
	scene.player.pos = minPos
	scene.player.minDist = minC
	scene.player.posXY = scene.centerLine.getPointAt(minPos)
	return minPos

calculateFuture = (scene, r, speed, currPos) ->
	t1 = 0
	if currPos?
		t1 = currPos
	th = scene.params.headway
	fut = [th, th, th, -0.1]
	for i from 0 til 5
		point = scene.centerLine.getPointAt(t1)
		dist = speed*fut[i]
		t2 = t1 + dist/scene.centerLine.getLength()*r
		if t2 >= 1
			scene.end = true if scene.params.direction == 1
			t2 -= 1
		if t2 < 0
			scene.end = true if scene.params.direction == -1
			t2 = 1 - Math.abs(t2)
		point2 = scene.centerLine.getPoint(t2)
		scene.predict[i] = point2

deparam = require 'jquery-deparam'
opts = deparam window.location.search.substring 1
xrad = Math.floor(opts.rx)
yrad = Math.floor(opts.ry)
length = Math.floor(opts.l)
speed = Math.floor(opts.s)
rev = Math.floor(opts.rev)
stat = Math.floor(opts.stat)
four = Math.floor(opts.four)
future = Math.floor(opts.fut)
tri = Math.floor(opts.tri)
automatic = Math.floor(opts.aut)
if speed === NaN
		speed = 60
if xrad === NaN
		xrad = ((speed/3.6)*22 / Math.PI)
if automatic === NaN
	automatic = 0
if yrad  === NaN
		yrad  = xrad
if length === NaN
		length = (speed/3.6)*8
if rev === NaN
		rev = 1
if stat === 1
		stat = true
else
	stat = false
if four === 1
		four = true
else
	four = false
if future === NaN
	future = 2
n = 4


export synch = seqr.bind (env, startMsg) ->*
	{controls, audioContext, L} = env
	scene = new Scene
	eye = new THREE.Object3D
	eye.position.x = 0
	eye.position.z = 0
	eye.position.y = 1.2
	eye.rotation.y = Math.PI
	scene.visual.add eye
	eye.add scene.camera


	scene.onStart ->
		env.container.addClass "hide-cursor"
	scene.onExit ->
		env.container.removeClass "hide-cursor"

	dark = addBackgroundColor scene, 0x000000
	light = addBackgroundColor scene, 0xffffff
	light.visible = false
	#scene.visual.add bg

	scene.preroll = seqr.bind ->*
		# Tick a couple of frames for the physics to settle
		t = Date.now()
		n = 100
		for [0 to n]
			scene.tick 1/60
		console.log "Prewarming FPS", (n/(Date.now() - t)*1000)


	@let \scene, scene
	yield @get \run
	start = scene.time

	i = 0

	scene.onTickHandled ~>
		i := i + 1
		if i % 60 == 0
			light.visible = true
			dark.visible = false
			env.logger.write flash: Date.now() / 100000.0
		if (i - 1)  % 60 == 0
			dark.visible = true
			light.visible = false
			env.logger.write flashEnd: Date.now() / 100000.0
		if scene.time - start > 20.5
				@let \done, passed: true, outro:
					title: env.L "Done"
				return false
	return yield @get \done


export calbrationScene = seqr.bind (env, startMsg) ->*
	{controls, audioContext, L} = env
	scene = new Scene
	eye = new THREE.Object3D
	eye.position.x = 0
	eye.position.z = 0
	eye.position.y = 1.2
	eye.rotation.y = Math.PI
	scene.visual.add eye
	eye.add scene.camera

	bg = addBackgroundColor scene
	scene.visual.add bg

	addCalibrationMarker scene
	addMarkerScreen scene, env
	/*
	opts = deparam window.location.search.substring 1
	url = "ws://169.254.219.68:10103"
	if opts.pupil?
		url = opts.pupil
	socket = new WebSocket url

	socket.onopen = ->
		console.log("socket open")
		socket.send("Webtrajsim here")
		scene.socket = socket
		if scene.start
			scene.socket.send startMsg

	socket.onmessage = (e) ->
		message = {"sceneTime": scene.time, "time": Date.now() / 1000, "position": scene.marker.position}
		message = JSON.stringify(message)
		scene.msg = e.data
		if scene.start
			socket.send message

	socket.onclose = ->
		console.log("socket closed")
		scene.socket = false


	env.controls.change (btn) ->
		if btn == "Xbox"
			env.vrcontrols.resetPose()
	*/
	scene.preroll = seqr.bind ->*
		# Tick a couple of frames for the physics to settle
		t = Date.now()
		n = 100
		for [0 to n]
			scene.tick 1/60
		console.log "Prewarming FPS", (n/(Date.now() - t)*1000)
	return scene

calibration = exportScenario \calibration, (env, mini = false) ->*
	scene = yield calbrationScene env, "start calibration"


	calibLocs = [ [-1.0, 0.4, -2.5], [0, 0.4, -2.5], [1.0, 0.4, -2],
			[-1.0, 0.2, -2.5], [0, 0.2, -2.5], [1.0, 0.2, -2],
			[-1.0, 0.0, -2.5], [-0.5, 0.0, -2.5], [0, 0.0, -2.5], [0.5, 0.0, -2.5], [1.0, 0.0, -2],
			[-1.0, -0.2, -2.5], [-0.5,-0.2, -2.5], [0, -0.2, -2.5], [0.5, -0.2, -2.5], [1.0, -0.2, -2],
			[-1.0, -0.4, -2.5], [0, -0.4, -2.5], [1.0, -0.4, -2]]

	calibLocs = [[-0.75, 0.0, -2.5], [0, 0.0, -2.5], [0.75, 0.0, -2.5],[-0.75,-0.2, -2.5], [0, -0.2, -2.5], [0.75, -0.2, -2.5]] if mini



	scene.marker.position.x = calibLocs[0][0]
	scene.marker.position.y = calibLocs[0][1]
	scene.marker.position.z = -3 #calibLocs[scene.marker.index][2]

	@let \scene, scene
	yield @get \run

	scene.start = false

	L = env.L
	i = 1
	text = '%calib.inst' + i.toString()
	yield ui.instructionScreen env, ->
		@ \title .append L "Calibration"
		@ \content .append L text
		@ \accept .text L "Ready"
		@ \progress .hide()
		@ \progressTitle .hide()


	#if scene.socket
	#	scene.socket.send "start calibration"




	change = scene.time
	scene.afterPhysics.add (dt) ->
		if scene.time - 3 > change
			scene.marker.index += 1
			scene.marker.position.x = calibLocs[scene.marker.index][0]
			scene.marker.position.y = calibLocs[scene.marker.index][1]
			scene.marker.position.z = -3 #calibLocs[scene.marker.index][2]
			marker = 
				x: scene.marker.position.x 
				y: scene.marker.position.y
				z: scene.marker.position.z
			env.logger.write marker: marker
			change := scene.time

	scene.onTickHandled ~>
		if scene.marker.index >= calibLocs.length - 1
			#if scene.socket
			#	scene.socket.send "stop"
			#	scene.socket.close()
			#exitVR env
			@let \done, passed: true, outro:
				title: env.L "Done"
			return false
	return yield @get \done

export instructions = seqr.bind (env, inst, scene) ->*
	L = env.L
	title = "Circle driving"
	text = "%circleDriving.intro"
	if inst == "prac"
		title = "Circle driving practice"
	if inst == "dark"
		title = "Dark driving"
		text = "%darkDriving.intro"
	if inst == "dark prac"
		title = "Dark driving practice"
		text = "%darkDriving.intro"
	dialogs =
		->
			@ \title .text L title
			@ \text .append L text
			@ \wrapper .0.style.height="4.0cm"
			@ \accept .text L "Next"
			@ \cancel-button .hide!
		->
			@ \title .text L title
			@ \text .append L "%circleDriving.intro2"
			@ \wrapper .0.style.height="3.5cm"
			@ \cancel .text L "Previous"
			@ \accept .text L "Next"
		->
			@ \title .text L title
			@ \text .append L "%circleDriving.intro3"
			@ \wrapper .0.style.height="2.8cm"
			@ \cancel .text L "Previous"
			@ \accept .text L "Ok"
	i = 0
	while i < dialogs.length
		result = yield ui.inputDialog env, dialogs[i]
		console.log result
		if i == 0 || i == 2
			scene.probes[3].stim[1].visible = true
			for j from 0 til 3
				seed = j+2
				scene.probes[j].stim[seed].visible = true
		else
			for j from 0 til 4
				for k from 1 til 6
					scene.probes[j].stim[k].visible = false
		if result.canceled
			i -= 2
		i += 1
	for j from 0 til 4
		for k from 1 til 6
			scene.probes[j].stim[k].visible = false

export briefInst = seqr.bind (env, inst, scene) ->*
	L = env.L
	title = "Circle driving"
	text = "%circleDriving.afterintro"
	if inst == "first"
		title = "Circle driving practice"
		text = "%circleDriving.intro"
	if inst == "dark"
		title = "Dark driving"
		text = "%darkDriving.afterintro"
	if inst == "dark still prac"
		title = "Dark driving practice"
		text = "%darkDriving.pracintro"
	dialogs =
		->
			@ \title .text L title
			@ \text .append L text
			@ \wrapper .0.style.height="4.0cm"
			@ \accept .text L "Ok"
			@ \cancel-button .hide!
	result = yield ui.inputDialog env, dialogs


addCalibrationMarker = (scene) ->
	tex = THREE.ImageUtils.loadTexture 'res/markers/CalibrationMarker.png'
	calibMaterial = new THREE.MeshBasicMaterial do
		color: 0xffffff
		map: tex
	geo = new THREE.CircleGeometry(0.1, 32)
	mesh = new THREE.Mesh geo, calibMaterial
	mesh.position.x = -0.5
	mesh.position.y = 0.5
	mesh.position.z = -3
	scene.camera.add mesh
	mesh.index = 0
	scene.marker = mesh




Stats = require './node_modules/stats.js'
export basecircleDriving = seqr.bind (env, params) ->*

	scene = yield circleScene env, params
	addMarkerScreen scene, env

	#stats = new Stats(0)
	#stats.domElement.style.position	= 'absolute'
	#stats.domElement.style.right	= '400px'
	#stats.domElement.style.bottom	= '40px'
	#document.body.appendChild stats.domElement

	#scene.onRender.add (dt) ->
	#	stats.update()

	#addBackgroundColor scene
	return scene

onInnerLane = (scene) ->
	pos = scene.centerLine.getPointAt(scene.player.pos)
	posActual = scene.player.physical.position
	c = ((posActual.z - pos.x) ^ 2 + (posActual.x - pos.y) ^ 2 ) ^ 0.5
	if c > 10
		scene.failed = true
		return true
	else if c > 1.75
		return false
	else
		return true

onOuterLane = (x, z, rX, rY, rW, l) ->
	if (((x ^ 2 / ((rX + 0.5*rW) ^ 2)  + (z ^ 2 / ((rY + 0.5*rW) ^ 2))) > 1)  && ((x ^ 2 / ((rX+rW) ^ 2)  + (z ^ 2 / ((rY+rW) ^ 2))) <= 1) && z >= 0)
			return true
	if (((x ^ 2 / ((rX + 0.5*rW) ^ 2)  + ((z+l) ^ 2 / ((rY + 0.5*rW) ^ 2))) > 1)  && ((x ^ 2 / ((rX+rW) ^ 2)  + ((z+l) ^ 2 / ((rY+rW) ^ 2))) <= 1) && z <= -l)
			return true
	if z <= 0 && z >= -l && x > rX + 0.5*rW && x < rX + rW
			return true
	if z <= 0 && z >= -l && x < -rX - 0.5*rW && x > -rX - rW
			return true
	else
		return false

handleSound = (sound, scene, cnt) ->
	if cnt == false and scene.time - scene.soundTs >= 1
		sound.play()
		scene.soundPlay = true
		scene.soundTs = scene.time
	else if scene.soundPlay == true && cnt == true
		sound.stop()
		scene.soundPlay = false

handleSteering = (scene, env) ->
	v1 = scene.player.physical.velocity
	pos = scene.player.body.position
	v2 = scene.predict[0]
	v1 = {x: v1.x , z: v1.z}
	v2 = {x: v2.y - pos.x, z: v2.x - pos.z}
	#c1 = (v1.x ^ 2 + v1.z ^2) ^ 0.5
	#c2 = (v2.x ^ 2 + v2.z ^ 2) ^ 0.5
	#dotProduct = (v1.x * v2.x) + (v1.z * v2.z)
	#angle = Math.acos((dotProduct) / (c1*c2))
	angle =  Math.atan2(v1.x, v1.z) - Math.atan2(v2.x, v2.z)
	angleMin = Math.min Math.abs(angle), Math.abs(Math.PI*2 - Math.abs(angle))
	if Math.abs(angleMin) != Math.abs(angle)
		angle = -Math.sign(angle)*angleMin
	scene.playerControls.steering = -angle


handleSpeed = (scene, target) ->
	speed = scene.player.getSpeed()*3.6
	force = scene.playerControls.throttle - scene.playerControls.brake
	dt = scene.time - scene.prevTime
	accel = (speed - scene.player.prevSpeed) / dt
	t = 1/(Math.abs(target - speed) ^ 0.5*3)
	accelTarget = (target - speed) / t
	delta = accelTarget - accel
	newForce = force + delta/50
	newForce = Math.max -1, newForce
	newForce = Math.min 1, newForce
	if newForce > 0
		scene.playerControls.throttle = newForce
		scene.playerControls.brake = 0
	else
		scene.playerControls.throttle = 0
		scene.playerControls.brake = -newForce

handleReaction = (env, scene, i) ->
	pYes = env.controls.pYes
	pNo = env.controls.pNo
	if scene.params.deviant == 1
		pYes = env.controls.pNo
		pNo = env.controls.pYes
	if pYes == true and scene.controlChange == true
		if scene.reacted == false
			scene.reacted = true
			scene.controlChange = false
			if scene.targetPresent == true
				scene.scoring.trueYes += 1
				scene.scoring.score += 1
				scene.probes[scene.target].score += 1
				scene.targetPresent = false
			else
				scene.scoring.falseYes += 1
				scene.scoring.score -= 1
			clearProbes scene
	if not pYes and not pNo and scene.reacted == false
		scene.controlChange = true

waypointFoil = (scene) ->
	wp_n = scene.params.waypoint_n
	wp = scene.adjInd%wp_n
	chance = Math.random()
	if wp == wp_n - 1 && wp_n == 5 && chance > 0.5
		scene.params.waypoint_n = 6
		scene.params.headway = 1 + (5.0/6.0)
		scene.adjInd = 6 - 1
	else if wp == wp_n - 1 && wp_n == 6
		scene.params.waypoint_n = 5
		scene.params.headway = 1 + (5.0/6.0)
		scene.adjInd = 5 - 1
	else 
		scene.params.headway = 2*(5/scene.params.waypoint_n)

addFixationCross = (scene, radius = 2.5, c = 0xFF0000, circle = false) ->
	vFOV = scene.camera.fov
	aspect = screen.width / screen.height
	angle = (vFOV/2) * Math.PI/180
	ratio = radius / (vFOV)
	size = (Math.tan(angle) * 1.7 * 2) * ratio

	fixObj = new THREE.Object3D()

	cycles = 18.0
	size = 1.0
	uniform = {cycles: { type: "f", value: cycles }, trans: {type: "f", value: 0.0}}

	#texture = new THREE.Texture assets.SineGratingBitmap resolution: 512, cycles: cycles
	#texture.magFilter = THREE.NearestFilter
	#texture.minFilter = THREE.LinearMipMapLinearFilter
	#texture.needsUpdate = true

	material = new THREE.ShaderMaterial vertexShader: document.getElementById( 'vertexShader' ).textContent, fragmentShader: document.getElementById( 'fragmentShader' ).textContent, transparent: true, uniforms: uniform
	#material.precision =  "highp"

	#material.polygonOffset = true
	#material.depthTest = true
	#material.polygonOffsetFactor = -1
	#material.polygonOffsetUnits = -1


	material.needsUpdate = true



	material = new THREE.MeshBasicMaterial side: THREE.DoubleSide, color: 0xFF0000,transparent: true, opacity: 1.0

	geo = new THREE.CircleGeometry(0.75, 32)
	circle = new THREE.Mesh geo, material
	#circle.position.y = size/2.0 + 0.1
	circle.rotation.x = -Math.PI*0.5
	#circle.receiveShadow = false
	#circle.castShadow = true

	fixObj.add circle
	#fixObj.add shadow
		


	fixObj.position.y = -10000
	fixObj.heigth = size
	fixObj.ratio = ratio
	scene.visual.add fixObj
	scene.fixcircles.push fixObj
	#objectLoc fixObj, -10.1, -10.1
	fixObj.visible = true

markersVisible = (scene) ->
	for marker in scene.markers
		marker.visible = true

addBackgroundColor = (scene, c = 0x7F7F7F) ->
	geo = new THREE.PlaneGeometry 4000, 4000
	mat = new THREE.MeshBasicMaterial color: c, depthTest: true
	mesh = new THREE.Mesh geo, mat
	mesh.position.z = -2100
	scene.camera.add mesh
	return mesh
	#console.log scene

addBackgroundColorFun = (scene) ->
	geo = new THREE.SphereGeometry 2000, 2000
	
	moonTex = THREE.ImageUtils.loadTexture 'res/world/moon.jpg'

	mat = new THREE.MeshPhongMaterial do
		map: moonTex
		shininess: 20
		transparent: true
		side: THREE.DoubleSide

	#mat = new THREE.MeshBasicMaterial color: 0xd3d3d3, depthTest: true
	mesh = new THREE.Mesh geo, mat
	#mesh.position.z = -1100
	mesh.rotation.y = 1.25*Math.PI
	#mesh.rotation.x = 2.5*Math.PI
	#mesh.rotation.z = 0.5*Math.PI
	mesh.position.y = 200
	scene.visual.add mesh
	#console.log scene



addMarkerScreen = (scene, env) ->
	aspect = screen.width / screen.height
	vFOV = scene.camera.fov
	angle = (vFOV/2) * Math.PI/180
	ratio = 0.1
	heigth = (Math.tan(angle) * 1.7 * 2) * ratio
	scene.markers = []
	pos = [[0.5 0.8], [1 - 0.15/aspect, 0.8], [0.15/aspect, 0.1], [1 - 0.15/aspect, 0.1], [1 - 0.15/aspect, 0.1], [0.15/aspect, 0.8], [0.5, 0.8]]
	for i from 0 til 6
		path = 'res/markers/' + (i) + '_marker.png'
		texture = THREE.ImageUtils.loadTexture path
		marker = new THREE.Mesh do
			new THREE.PlaneGeometry heigth, heigth
			new THREE.MeshBasicMaterial map:texture, transparent: true, depthTest: true, depthWrite: true, opacity: 1.0
		#new THREE.MeshBasicMaterial map:texture, transparent: true, depthTest: false, depthWrite: false
		marker.position.z = -1.7

		h = 1/ratio * heigth
		w = aspect * h
		marker.position.x = (w*(pos[i][0]) - w/2)
		marker.position.y = (h*pos[i][1] - h/2)
		scene.camera.add marker
		scene.markers.push marker
		marker.visible = true

prevOrder = (order) ->
	previews = [[false, true, false, true, false, false, true, true, true, true, false, false, true, true, false, true, false, false, false, true],[true, false, false, false, false, true, true, false, false, true, false, false, false, true, true, true, true, false, true, false],[false, true, false, false, true, false, true, true, false, false, false, true, false, false, false, true, false, false, true, true],[true, true, false, true, true, false, false, false, false, true, false, false, true, true, false, true, true, true, false, false],[false, false, false, true, true, true, false, true, false, true, false, true, true, true, false, true, true, true, false, false],[true, true, false, true, false, false, false, true, false, true, true, true, true, true, true, true, false, false, true, false],[false, false, true, true, true, false, false, true, false, true, false, false, false, true, true, false, false, false, true, true],[true, false, true, true, true, false, false, true, true, false, false, false, true, true, false, false, true, false, true, false],[true, true, true, true, false, false, true, true, false, false, true, false, false, true, false, false, true, true, false, true],[true, false, false, true, false, true, false, true, true, false, true, false, true, false, true, false, true, false, false, true]]
	return previews[order]

probeOrder = (order, turn, degrees60 = true) ->

	#6 of each on 60 degrees
	p_orders = [
			[1, 0, 4, 4, 4, 3, 3, 4, 3, 2, 1, 0, 4, 3, 0, 2, 1, 0, 4, 1, 3, 2, 2, 1, 0, 0, 2, 3, 2, 1],
			[0, 4, 3, 3, 1, 0, 0, 4, 3, 2, 4, 3, 2, 1, 1, 2, 2, 2, 1, 0, 4, 0, 4, 3, 4, 3, 0, 1, 2, 1],
			[2, 1, 0, 4, 3, 2, 3, 2, 1, 2, 1, 0, 0, 0, 0, 4, 4, 3, 2, 1, 1, 2, 1, 0, 4, 3, 3, 4, 4, 3],
			[1, 0, 0, 4, 2, 2, 3, 2, 1, 0, 4, 3, 3, 2, 3, 2, 1, 1, 2, 1, 0, 4, 3, 0, 4, 0, 4, 3, 4, 1],
			[4, 4, 3, 4, 4, 3, 2, 3, 3, 2, 1, 0, 0, 4, 3, 3, 2, 2, 1, 0, 1, 0, 0, 2, 1, 1, 0, 4, 2, 1],
			[1, 3, 4, 3, 2, 3, 2, 4, 0, 0, 4, 3, 2, 1, 0, 4, 3, 2, 1, 0, 1, 0, 4, 0, 2, 3, 2, 1, 1, 4],
			[0, 2, 3, 2, 2, 1, 0, 0, 1, 0, 0, 4, 3, 2, 4, 4, 4, 3, 3, 3, 2, 1, 1, 2, 1, 0, 4, 1, 4, 3],
			[3, 2, 2, 4, 3, 2, 1, 1, 0, 4, 3, 3, 0, 1, 0, 0, 1, 4, 3, 2, 1, 1, 0, 0, 4, 3, 2, 2, 4, 4],
			[3, 2, 1, 1, 0, 0, 0, 4, 4, 0, 4, 3, 4, 3, 2, 1, 0, 2, 2, 1, 4, 3, 3, 2, 1, 0, 4, 3, 2, 1],
			[4, 4, 3, 4, 1, 0, 4, 3, 2, 1, 0, 4, 3, 2, 2, 3, 2, 2, 1, 3, 1, 0, 0, 0, 4, 1, 3, 2, 1, 0],
			[2, 1, 0, 2, 4, 3, 2, 1, 0, 0, 4, 3, 2, 1, 0, 3, 2, 1, 0, 4, 4, 4, 0, 3, 4, 3, 2, 1, 1, 3],
			[3, 4, 3, 2, 1, 2, 2, 2, 0, 0, 1, 1, 1, 0, 4, 4, 3, 2, 1, 0, 4, 3, 2, 0, 1, 0, 4, 3, 4, 3],
			[2, 2, 1, 0, 4, 3, 3, 3, 2, 2, 3, 3, 4, 4, 3, 4, 0, 4, 0, 2, 1, 1, 0, 0, 1, 2, 1, 1, 0, 4],
			[1, 2, 1, 1, 0, 4, 3, 2, 2, 2, 3, 0, 4, 3, 3, 2, 4, 0, 0, 0, 0, 1, 4, 4, 3, 4, 3, 2, 1, 1],
			[1, 0, 4, 4, 3, 2, 1, 1, 0, 0, 4, 3, 2, 3, 2, 1, 3, 2, 2, 2, 1, 1, 0, 0, 0, 3, 4, 4, 4, 3]
			]
	probes = p_orders[order]
	if degrees60
		return probes
	p_orders = [[2, 1, 5, 5, 3, 3, 3, 0, 4, 2, 6, 4, 3, 2, 6, 1, 0, 0, 6, 4, 1, 0, 5, 2, 6, 4, 1, 5],
				[2, 6, 3, 1, 5, 4, 2, 0, 6, 3, 0, 6, 3, 2, 0, 4, 1, 1, 5, 3, 0, 4, 4, 1, 5, 5, 2, 6],
				[5, 2, 6, 3, 0, 0, 6, 3, 0, 4, 1, 6, 3, 2, 6, 3, 1, 5, 4, 2, 1, 0, 4, 1, 5, 2, 4, 5],
				[3, 1, 6, 3, 2, 2, 0, 1, 5, 3, 0, 5, 2, 0, 4, 2, 6, 6, 6, 4, 1, 0, 4, 4, 3, 1, 5, 5],
				[1, 6, 4, 1, 5, 1, 5, 3, 0, 4, 3, 0, 4, 5, 2, 1, 0, 2, 2, 6, 3, 2, 6, 6, 4, 3, 0, 5],
				[1, 6, 3, 3, 0, 5, 2, 6, 3, 0, 4, 1, 5, 4, 5, 2, 6, 3, 0, 6, 4, 2, 1, 5, 2, 0, 4, 1],
				[2, 0, 4, 1, 5, 3, 0, 4, 2, 3, 1, 5, 4, 6, 2, 6, 4, 1, 1, 5, 3, 0, 0, 5, 2, 6, 6, 3],
				[2, 0, 6, 3, 0, 3, 1, 0, 4, 3, 2, 6, 4, 1, 5, 2, 0, 4, 1, 5, 2, 6, 3, 5, 6, 4, 1, 5],
				[0, 4, 1, 5, 2, 1, 5, 4, 3, 6, 3, 5, 2, 6, 4, 1, 3, 0, 5, 3, 2, 0, 6, 0, 4, 1, 2, 6],
				[5, 4, 1, 6, 6, 3, 0, 4, 2, 3, 1, 2, 0, 6, 3, 1, 5, 2, 0, 4, 1, 5, 4, 6, 3, 0, 5, 2],
				[0, 2, 6, 3, 2, 0, 4, 2, 6, 4, 1, 5, 3, 1, 6, 3, 0, 6, 4, 2, 0, 5, 3, 4, 1, 1, 5, 5],
				[5, 2, 0, 4, 0, 4, 2, 6, 6, 3, 0, 4, 1, 6, 3, 0, 4, 2, 1, 6, 5, 3, 1, 1, 5, 2, 5, 3]
				]


	probes = p_orders[order]
	return probes
	

exportScenario \fixSwitch, (env, {hide=false, turn=-1, n=0, allVisible = false, dur = 130, trackID = 0}={}) ->*

	listener = new THREE.AudioListener()
	console.log hide, turn, n, allVisible
	annoyingSound = new THREE.Audio(listener)
	annoyingSound.load('res/sounds/beep.wav')
	annoyingSound.setVolume(0.05)

	annoyingSound2 = new THREE.Audio(listener)
	annoyingSound2.load('res/sounds/beep-01a.wav')
	annoyingSound2.setVolume(0.05)
	degrees60 = false

	l = 0

	s = 100
	rx = s/(Math.PI/4.5*3.6)
	ry = rx

	wp_n = 7

	if turn == undefined
		turn = -1
	if hide == undefined
		hide = false
	if env.opts.hideRoad
		hide = env.opts.hideRoad > 0
	if n == undefined
		n = 0
	if allVisible == undefined
		allVisible = false
	if env.opts.allVisible
		allVisible = true
	if n == -1
		n = Math.floor(Math.random() * (8 - 0 + 1)) + 0

	order = probeOrder n, turn, degrees60
	previews = prevOrder n
	params = {major_radius: rx, minor_radius: ry, straight_length: l, target_speed: s, direction: 1, duration: dur, updateTime: 1.0, headway: 2.0, targets: 4, probes: order, previews: previews, ident: n, firstTurn: turn, hide: hide, waypoint_n: wp_n, no_missing: allVisible, track: trackID}
	console.log params
	scene = yield basecircleDriving env, params
	scene.lastSlowSearch = -5
	scene.lastMiss = -100

	scene.params = params
	env.logger.write scenarioParams: scene.params


	scene.fixcircles = []
	addFixationCross scene, 1.5
	addFixationCross scene, 1.5
	addFixationCross scene, 1.5
	addFixationCross scene, 1.5
	
	scene.random = 0
	#scene.fixcircles[0].children[0].material.color.g = 1.0
	#scene.fixcircles[3].children[0].material.color.r = 1.0

	startPoint = 0
	scene.player.physical.position.x = scene.centerLine.getPointAt(startPoint).y
	scene.startX = scene.player.physical.position.x 
	scene.player.physical.position.z = scene.centerLine.getPointAt(startPoint).x
	if turn != -1
		scene.player.physical.quaternion.setFromEuler(0, Math.PI ,0, 'XYZ')
	scene.playerControls.throttle = 0


	title = "%fixSwitchPrac.title" 
	text = "%fixSwitchPrac.intro" #aukot voi olla eripitusia

	title = "%fixSwitch.title" if dur == 155
	text = "%fixSwitchGaps.intro" if hide
	text = "%fixSwitchGapless.intro" if (hide && allVisible)


	markersVisible scene
	calculateFuture scene, 1, s/3.6
	handleFixLocs scene
	search(scene)
	fixLogic env, scene, annoyingSound, s
	#rotateObjects scene

	scene.visibTime = 2

	@let \intro,
		title: env.L title
		content: env.L text

	rw = scene.centerLine.width
	@let \scene, scene
	yield @get \run





	startTime = scene.time
	scene.prevOp = startTime
	scene.dT = startTime
	scene.probeIndx = 0
	scene.adjInd = 0

	scene.roadSecond = (s/3.6) /  scene.centerLine.getLength()
	scene.futPos = startPoint
	#futPos scene

	scene.fixcircles = []
	for i from 0 til dur + 5
		currPos = scene.futPos
		futPos scene
		addFixationCross scene, 1.5
		calculateFuture scene, 1, s/3.6, currPos
		handleFixLocs scene, i
		console.log scene.fixcircles[i].position.x
		if i > 0
			scene.fixcircles[i].position.y = -100
		if Math.abs(scene.fixcircles[i].position.x - scene.startX) > 1 && i> 1 && scene.fixcircles[i - 1].turn_wp == false && scene.fixcircles[i - 2].turn_wp == false
			scene.fixcircles[i].turn_wp = true
			scene.fixcircles[i].position.y = 1
		else
			scene.fixcircles[i].turn_wp = false
	scene.futPos = startPoint
	futPos scene

	while not env.controls.catch == true
		yield P.delay 100

	scene.onTickHandled ~>

		#if (scene.time - scene.prevOp) > 0.5
		#	scene.prevOp = scene.time
		#	scene.road.material.opacity = Math.max scene.road.material.opacity - 0.005, 0
		handleSpeed scene, s

		search(scene)
		fixLogic env, scene, annoyingSound, s
		#rotateObjects scene

		z = scene.player.physical.position.z
		x = scene.player.physical.position.x
		cnt = onInnerLane scene

		if cnt == false
			scene.outside.out = true
			scene.outside.totalTime += scene.time - scene.prevTime
		else
			scene.outside.out = false


		handleSound annoyingSound2, scene, cnt

		scene.prevTime = scene.time
		scene.player.prevSpeed = scene.player.getSpeed()*3.6

		if scene.failed
			listener.remove()
			@let \done, passed: false, outro:
				title: env.L "Oops!"
				content: env.L 'You steered off the course'
			return false

		if scene.end == true || (scene.time - startTime) > 300
			trialTime = scene.time - startTime
			listener.remove()
			@let \done, passed: true, outro:
				title: env.L "Passed"
				content: """
				<p>Suoritus kesti #{trialTime.toFixed 2} sekuntia.</p>
                <p>Olit kokonaisuudessaan #{scene.outside.totalTime.toFixed 2} sekuntia tien ulkopuolella.</p>
				 """
			return false

	return yield @get \done

exportScenario \experimentOutro, (env, cb=->) ->*
	L = env.L
	yield ui.instructionScreen env, (...args) ->
		@ \title .append L "The experiment is done!"
		@ \content .append L '%experimentOutro'
		@ \accept-button .hide()
		cb.apply @, [env].concat ...args


exportScenario \circleDriving, (env, rx, ry, l, s, r, st, col, fut, inst, dev, aut, visib) ->*

	if rx == undefined
		rx = xrad
	if ry == undefined
		ry = yrad
	if l == undefined
		l = length
	if s == undefined
		s = speed
	if r == undefined
		r = rev
	if st == undefined
		st = stat
	if fr == undefined
		fr = four
	if fut == undefined
		fut = future
	if aut == undefined
		aut = automatic
	if visib == undefined
		visib = 1.0

	settingParams = {major_radius: rx, minor_radius: ry, straight_length: l, target_speed: s, direction: 1, static_probes: st, four: fr, future: fut, automatic: aut, deviant: dev, duration: 120}

	scene = yield basecircleDriving env, rx, ry, l

	scene.params = settingParams
	addFixationCross scene
	addMarkerScreen scene, env

	probeOrder scene, n
	createProbes scene, n
	if col == true
		colorProbes scene

	startPoint = 0.5*l/scene.centerLine.getLength()
	scene.player.physical.position.x = scene.centerLine.getPointAt(startPoint).y
	scene.player.physical.position.z = -0.5*l
	scene.playerControls.throttle = 0
	#startLight = yield assets.TrafficLight()
	#lightX = (rx ^ 2 - 5 ^ 2)^0.5 - 0.25
	#startLight.position.x = lightX
	#startLight.position.z = 7.5
	#startLight.addTo scene
	rw = scene.centerLine.width
	@let \scene, scene
	yield @get \run

	calculateFuture scene, 1, s/3.6
	handleProbeLocs scene, n, r, fut
	markersVisible scene

	scene.visibTime = visib

	unless inst == false
		yield briefInst env, inst, scene

	while not env.controls.catch == true
			yield P.delay 100
	env.controls.probeReact = false

	#yield startLight.switchToGreen()

	startTime = scene.time
	scene.dT = startTime
	scene.probeIndx = 0
	scene.roadSecond = (scene.params.target_speed/3.6) /  scene.centerLine.getLength()
	scene.futPos = startPoint
	futPos scene
	scene.beforePhysics.add ->
			if aut == 1
				handleSteering scene, env

	scene.onTickHandled ~>
		handleSpeed scene, s
		calculateFuture scene, 1, s/3.6
		unless st == true
			handleProbeLocs scene, n, r, fut

		i = 0

		handleReaction env, scene, i
		probeLogic scene, n

		z = scene.player.physical.position.z
		x = scene.player.physical.position.x
		cnt = onInnerLane scene

		if cnt == false
			scene.outside.out = true
			scene.outside.totalTime += scene.time - scene.prevTime
		else
			scene.outside.out = false


		handleSound annoyingSound, scene, cnt

		scene.prevTime = scene.time
		scene.player.prevSpeed = scene.player.getSpeed()*3.6

		if scene.end == true || (scene.time - startTime) > 300
			trialTime = scene.time - startTime
			correct = scene.scoring.score/scene.scoring.maxScore * 100
			listener.remove()
			@let \done, passed: true, outro:
				title: env.L "Passed"
				content: """
				<p>Sait vastauksista #{correct.toFixed 2}% oikein.</p>
				<p>Suoritus kesti #{trialTime.toFixed 2} sekunttia.</p>
				 """
			return false

	return yield @get \done

exportScenario \circleDrivingRev, (env, rx, ry, l, s, r, st, col, fut, inst, dev, aut, visib) ->*

	if rx == undefined
		rx = xrad
	if ry == undefined
		ry = yrad
	if l == undefined
		l = length
	if s == undefined
		s = speed
	if r == undefined
		r = -rev
	if st == undefined
		st = stat
	if fr == undefined
		fr = four
	if fut == undefined
		fut = future
	if aut == undefined
		aut = automatic
	if visib == undefined
		visib = 1.0

	settingParams = {major_radius: rx, minor_radius: ry, straight_length: l, target_speed: s, direction: -1, static_probes: st, four: fr, future: fut, automatic: aut, deviant: dev, duration: 120}

	scene = yield basecircleDriving env, rx, ry, l

	scene.params = settingParams
	addFixationCross scene
	addMarkerScreen scene, env

	probeOrder scene, n
	createProbes scene, n
	if col == true
		colorProbes scene

	startPoint = 1 -(0.5*l/scene.centerLine.getLength())
	scene.player.physical.position.x = scene.centerLine.getPointAt(startPoint).y
	scene.player.physical.position.z =  -0.5*l
	scene.playerControls.throttle = 0
	#startLight = yield assets.TrafficLight()
	#lightX = (rx  ^ 2 - 5 ^ 2)^0.5 - 0.25
	#startLight.position.x = -lightX
	#startLight.position.z = 7.5
	#startLight.addTo scene
	rw = scene.centerLine.width
	markersVisible scene

	@let \scene, scene
	yield @get \run

	calculateFuture scene, -1, s/3.6
	handleProbeLocs scene, n, r, fut

	scene.visibTime = visib


	unless inst == false
		yield briefInst env, inst, scene

	while not env.controls.catch == true
			yield P.delay 100
	env.controls.probeReact = false

	#yield startLight.switchToGreen()

	startTime = scene.time
	scene.dT = startTime
	scene.probeIndx = 0
	scene.roadSecond = (scene.params.target_speed/3.6) /  scene.centerLine.getLength()
	scene.futPos = startPoint
	futPos scene

	scene.beforePhysics.add ->
		if aut == 1
			handleSteering scene, env

	scene.onTickHandled ~>
		handleSpeed scene, s
		calculateFuture scene, -1, s/3.6
		unless st == true
			handleProbeLocs scene, n, r, fut

		i = 0

		handleReaction env, scene, i
		probeLogic scene, n

		z = scene.player.physical.position.z
		x = scene.player.physical.position.x
		cnt = onInnerLane scene
		handleSound annoyingSound, scene, cnt

		if cnt == false
			scene.outside.out = true
			scene.outside.totalTime += scene.time - scene.prevTime
		else
			scene.outside.out = false

		scene.prevTime = scene.time
		scene.player.prevSpeed = scene.player.getSpeed()*3.6

		if scene.end == true || (scene.time - startTime) > 300
			listener.remove()
			correct = scene.scoring.score/scene.scoring.maxScore*100
			trialTime = scene.time - startTime
			@let \done, passed: true, outro:
				title: env.L "Passed"
				content: """
				<p>Sait vastauksista #{correct.toFixed 2}% oikein.</p>
				<p>Suoritus kesti #{trialTime.toFixed 2} sekunttia.</p>
				 """
			return false

	return yield @get \done


exportScenario \circleDrivingFree, (env, rx, ry, l, s, r, st, col, fut, inst, dev, aut) ->*

	if rx == undefined
		rx = xrad
	if ry == undefined
		ry = yrad
	if l == undefined
		l = length
	if s == undefined
		s = speed
	if r == undefined
		r = rev
	if st == undefined
		st = stat
	if fr == undefined
		fr = four
	if fut == undefined
		fut = future
	if aut == undefined
		aut = automatic

	settingParams = {major_radius: rx, minor_radius: ry, straight_length: l, target_speed: s, direction: 1, static_probes: st, four: fr, future: fut, automatic: aut, deviant: dev}

	scene = yield basecircleDriving env, rx, ry, l

	scene.params = settingParams
	addMarkerScreen scene, env


	startPoint = 0.5*l/scene.centerLine.getLength()
	scene.player.physical.position.x = scene.centerLine.getPointAt(startPoint).y
	scene.player.physical.position.z = -0.5*l
	scene.playerControls.throttle = 0
	#startLight = yield assets.TrafficLight()
	#lightX = (rx ^ 2 - 5 ^ 2)^0.5 - 0.25
	#startLight.position.x = lightX
	#startLight.position.z = 7.5
	#startLight.addTo scene
	rw = scene.centerLine.width

	@let \scene, scene
	yield @get \run

	while not env.controls.catch == true
			yield P.delay 100
	env.controls.probeReact = false

	#yield startLight.switchToGreen()

	startTime = scene.time
	scene.dT = startTime
	scene.probeIndx = 0
	scene.roadSecond = (scene.params.target_speed/3.6) /  scene.centerLine.getLength()
	scene.futPos = startPoint
	futPos scene
	scene.beforePhysics.add ->
			if aut == 1
				handleSteering scene, env

	scene.onTickHandled ~>
		handleSpeed scene, s
		calculateFuture scene, 1, s/3.6

		z = scene.player.physical.position.z
		x = scene.player.physical.position.x
		cnt = onInnerLane scene

		if cnt == false
			scene.outside.out = true
			scene.outside.totalTime += scene.time - scene.prevTime
		else
			scene.outside.out = false


		handleSound annoyingSound, scene, cnt

		scene.prevTime = scene.time
		scene.player.prevSpeed = scene.player.getSpeed()*3.6

		if scene.end == true || (scene.time - startTime) > 120
			trialTime = scene.time - startTime
			listener.remove()
			@let \done, passed: true, outro:
				title: env.L "Passed"
				content: """
				<p>Suoritus kesti #{trialTime.toFixed 2} sekunttia.</p>
				 """
			return false

	return yield @get \done

exportScenario \circleDrivingRevFree, (env, rx, ry, l, s, r, st, col, fut, inst, dev, aut) ->*

	if rx == undefined
		rx = xrad
	if ry == undefined
		ry = yrad
	if l == undefined
		l = length
	if s == undefined
		s = speed
	if r == undefined
		r = -rev
	if st == undefined
		st = stat
	if fr == undefined
		fr = four
	if fut == undefined
		fut = future
	if aut == undefined
		aut = automatic

	settingParams = {major_radius: rx, minor_radius: ry, straight_length: l, target_speed: s, direction: -1, static_probes: st, four: fr, future: fut, automatic: aut, deviant: dev}

	scene = yield basecircleDriving env, rx, ry, l

	scene.params = settingParams
	addMarkerScreen scene, env
	startPoint = 1 -((scene.centerLine.curves[1].getLength()*2 + 1.5*l)/scene.centerLine.getLength())
	scene.player.physical.position.x = scene.centerLine.getPointAt(startPoint).y
	scene.player.physical.position.z =  -0.5*l
	scene.playerControls.throttle = 0
	#startLight = yield assets.TrafficLight()
	#lightX = (rx  ^ 2 - 5 ^ 2)^0.5 - 0.25
	#startLight.position.x = -lightX
	#startLight.position.z = 7.5
	#startLight.addTo scene
	rw = scene.centerLine.width

	@let \scene, scene
	yield @get \run

	unless inst == false
		yield instructions env, inst, scene

	while not env.controls.catch == true
			yield P.delay 100
	env.controls.probeReact = false

	#yield startLight.switchToGreen()

	startTime = scene.time
	scene.dT = startTime
	scene.probeIndx = 0
	scene.roadSecond = (scene.params.target_speed/3.6) /  scene.centerLine.getLength()
	scene.futPos = startPoint
	futPos scene

	scene.beforePhysics.add ->
		if aut == 1
			handleSteering scene, env

	scene.onTickHandled ~>
		handleSpeed scene, s
		calculateFuture scene, -1, s/3.6

		z = scene.player.physical.position.z
		x = scene.player.physical.position.x
		cnt = onInnerLane scene
		handleSound annoyingSound, scene, cnt

		if cnt == false
			scene.outside.out = true
			scene.outside.totalTime += scene.time - scene.prevTime
		else
			scene.outside.out = false

		scene.prevTime = scene.time
		scene.player.prevSpeed = scene.player.getSpeed()*3.6

		if scene.end == true || (scene.time - startTime) > 120
			listener.remove()
			trialTime = scene.time - startTime
			@let \done, passed: true, outro:
				title: env.L "Passed"
				content: """
				<p>Suoritus kesti #{trialTime.toFixed 2} sekunttia.</p>
				 """
			return false

	return yield @get \done

exportScenario \darkDriving, (env, rx, ry, l, s, r, st, col, fut, inst, dev, aut, visib) ->*

	if rx == undefined
		rx = xrad
	if ry == undefined
		ry = yrad
	if l == undefined
		l = length
	if s == undefined
		s = speed
	if r == undefined
		r = rev
	if st == undefined
		st = stat
	if fr == undefined
		fr = four
	if fut == undefined
		fut = future
	if visib == undefined
		visib = 1.0

	aut = 1

	settingParams = {major_radius: rx, minor_radius: ry, straight_length: l, target_speed: s, direction: 1, static_probes: st, four: fr, future: fut, automatic: aut, deviant: dev, duration: 120}

	scene = yield basecircleDriving env, rx, ry, l, false

	scene.params = settingParams
	addFixationCross scene
	addBackgroundColor scene
	addMarkerScreen scene, env

	probeOrder scene, n
	createProbes scene, n
	if col == true
		colorProbes scene

	startPoint = 0.5*l/scene.centerLine.getLength()
	scene.player.physical.position.x = scene.centerLine.getPointAt(startPoint).y
	scene.player.physical.position.z = -0.5*l
	scene.playerControls.throttle = 0
	#startLight = yield assets.TrafficLight()
	#lightX = (rx ^ 2 - 5 ^ 2)^0.5 - 0.25
	#startLight.position.x = lightX
	#startLight.position.z = 7.5
	#startLight.addTo scene
	rw = scene.centerLine.width
	@let \scene, scene
	yield @get \run

	calculateFuture scene, 1, s/3.6
	handleProbeLocs scene, n, r, fut
	markersVisible scene

	scene.visibTime = visib

	unless inst == false
		if inst == "dark prac"
			yield instructions env, inst, scene
		else
			yield briefInst env, inst, scene


	while not env.controls.catch == true
			yield P.delay 100
	env.controls.probeReact = false

	#yield startLight.switchToGreen()

	startTime = scene.time
	scene.dT = startTime
	scene.probeIndx = 0
	scene.roadSecond = (scene.params.target_speed/3.6) /  scene.centerLine.getLength()
	scene.futPos = startPoint
	futPos scene
	scene.beforePhysics.add ->
			if aut == 1
				handleSteering scene, env

	scene.onTickHandled ~>
		handleSpeed scene, s
		calculateFuture scene, 1, s/3.6
		unless st == true
			handleProbeLocs scene, n, r, fut

		i = 0

		handleReaction env, scene, i
		probeLogic scene, n

		z = scene.player.physical.position.z
		x = scene.player.physical.position.x
		cnt = onInnerLane scene

		if cnt == false
			scene.outside.out = true
			scene.outside.totalTime += scene.time - scene.prevTime
		else
			scene.outside.out = false


		handleSound annoyingSound, scene, cnt

		scene.prevTime = scene.time
		scene.player.prevSpeed = scene.player.getSpeed()*3.6

		if scene.end == true || (scene.time - startTime) > 300
			trialTime = scene.time - startTime
			correct = scene.scoring.score/scene.scoring.maxScore * 100
			listener.remove()
			@let \done, passed: true, outro:
				title: env.L "Passed"
				content: """
				<p>Sait vastauksista #{correct.toFixed 2}% oikein.</p>
				<p>Suoritus kesti #{trialTime.toFixed 2} sekunttia.</p>
				 """
			return false

	return yield @get \done

exportScenario \darkDrivingRev, (env, rx, ry, l, s, r, st, col, fut, inst, dev, aut, visib) ->*

	if rx == undefined
		rx = xrad
	if ry == undefined
		ry = yrad
	if l == undefined
		l = length
	if s == undefined
		s = speed
	if r == undefined
		r = -rev
	if st == undefined
		st = stat
	if fr == undefined
		fr = four
	if fut == undefined
		fut = future
	if visib == undefined
		visib = 1.0

	aut = 1

	settingParams = {major_radius: rx, minor_radius: ry, straight_length: l, target_speed: s, direction: -1, static_probes: st, four: fr, future: fut, automatic: aut, deviant: dev, duration: 120}

	scene = yield basecircleDriving env, rx, ry, l, false

	scene.params = settingParams
	addFixationCross scene
	addBackgroundColor scene
	addMarkerScreen scene, env

	probeOrder scene, n
	createProbes scene, n
	if col == true
		colorProbes scene

	startPoint = 1 -(0.5*l/scene.centerLine.getLength())
	scene.player.physical.position.x = scene.centerLine.getPointAt(startPoint).y
	scene.player.physical.position.z =  -0.5*l
	scene.playerControls.throttle = 0
	#startLight = yield assets.TrafficLight()
	#lightX = (rx  ^ 2 - 5 ^ 2)^0.5 - 0.25
	#startLight.position.x = -lightX
	#startLight.position.z = 7.5
	#startLight.addTo scene
	rw = scene.centerLine.width
	markersVisible scene

	@let \scene, scene
	yield @get \run

	calculateFuture scene, -1, s/3.6
	handleProbeLocs scene, n, r, fut

	scene.visibTime = visib


	unless inst == false
		if inst == "dark prac"
			yield instructions env, inst, scene
		else
			yield briefInst env, inst, scene

	while not env.controls.catch == true
			yield P.delay 100
	env.controls.probeReact = false

	#yield startLight.switchToGreen()

	startTime = scene.time
	scene.dT = startTime
	scene.probeIndx = 0
	scene.roadSecond = (scene.params.target_speed/3.6) /  scene.centerLine.getLength()
	scene.futPos = startPoint
	futPos scene

	scene.beforePhysics.add ->
		if aut == 1
			handleSteering scene, env

	scene.onTickHandled ~>
		handleSpeed scene, s
		calculateFuture scene, -1, s/3.6
		unless st == true
			handleProbeLocs scene, n, r, fut

		i = 0

		handleReaction env, scene, i
		probeLogic scene, n

		z = scene.player.physical.position.z
		x = scene.player.physical.position.x
		cnt = onInnerLane scene
		handleSound annoyingSound, scene, cnt

		if cnt == false
			scene.outside.out = true
			scene.outside.totalTime += scene.time - scene.prevTime
		else
			scene.outside.out = false

		scene.prevTime = scene.time
		scene.player.prevSpeed = scene.player.getSpeed()*3.6

		if scene.end == true || (scene.time - startTime) > 300
			listener.remove()
			correct = scene.scoring.score/scene.scoring.maxScore*100
			trialTime = scene.time - startTime
			@let \done, passed: true, outro:
				title: env.L "Passed"
				content: """
				<p>Sait vastauksista #{correct.toFixed 2}% oikein.</p>
				<p>Suoritus kesti #{trialTime.toFixed 2} sekunttia.</p>
				 """
			return false

	return yield @get \done


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



addMirror = (scene, env) ->
	mirror = new THREE.Mirror(env.renderer, scene.camera, { clipBias: 0.0, textureWidth: window.innerWidth, textureHeight: window.innerHeight, debugMode: true})
	mirrorMesh = new THREE.Mesh do
		new THREE.PlaneBufferGeometry 0.5, 0.5
		mirror.material

	mirrorMesh.position.y = 0 
	mirrorMesh.position.x = 0.5
	mirrorMesh.position.z = -1.43 
	#mirrorMesh.rotation.y = -Math.PI*0.45
	
	mirrorMesh.add mirror



	scene.camera.add mirrorMesh

	scene.mirror = mirror
	scene.beforeRender.add (dt) ->
		mirror.renderer = env.renderer
		mirror.render()

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
			@ \title .text L "Participation is voluntary"
			@ \text .append L "%intro.participantRights"
			@ \cancel .text L "Previous"
			@ \accept .text L "I wish to participate"
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
		@ \progress .hide()
		@ \progressTitle .hide()
		cb.apply @, [env].concat ...args


exportScenario \calibrationInst, (env, i) ->*
	L = env.L
	text = '%calib.inst' + i.toString()
	yield ui.instructionScreen env, ->
		@ \title .append L "Calibration"
		@ \content .append L text
		@ \accept .text L "Ready"
		@ \progress .hide()
		@ \progressTitle .hide()


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

	rendererStats = new THREEx.RendererStats()
	rendererStats.domElement.style.position	= 'absolute'
	rendererStats.domElement.style.right = '100px'
	rendererStats.domElement.style.top = '100px'
	stats = new Stats()
	stats.domElement.style.position	= 'absolute'
	stats.domElement.style.right	= '400px'
	stats.domElement.style.bottom	= '40px'
	document.body.appendChild stats.domElement
	document.body.appendChild rendererStats.domElement
	scene.onRender.add (dt) ->
		rendererStats.update env.renderer
		stats.update()

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
