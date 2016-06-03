P = require 'bluebird'
Co = P.coroutine
$ = require 'jquery'
seqr = require './seqr.ls'

{addGround, Scene} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{NonSteeringControl, NonThrottleControl} = require './controls.ls'
{DefaultEngineSound, BellPlayer, NoisePlayer} = require './sounds.ls'
{circleScene} = require './circleScene.ls'
{NonSteeringControl} = require './controls.ls'
{DefaultEngineSound, BellPlayer, NoisePlayer} = require './sounds.ls'
assets = require './assets.ls'
prelude = require 'prelude-ls'

require './three.js/examples/fonts/Digital-7_Regular.typeface.js'
require './three.js/examples/fonts/Snellen_Regular.typeface.js'

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

	player = yield addVehicle scene, controls, objectName: 'player'
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

	scene.preroll = ->
		# Tick a couple of frames for the physics to settle
		scene.tick 1/60
		n = 100
		t = Date.now()
		for [0 to n]
			scene.tick 1/60
		console.log "Prewarming FPS", (n/(Date.now() - t)*1000)
	return scene

export minimalScenario = seqr.bind (env) ->*
	scene = new Scene
	addGround scene
	scene.preroll = ->
	@let \scene, scene
	yield @get \done

exportScenario \freeDriving, (env) ->*
	# Load the base scene
	scene = yield baseScene env

	# The scene would be customized here

	# "Return" the scene to the caller, so they know
	# we are ready
	@let \scene, scene

	scene.prevTime = 0

	scene.onTickHandled ~>
		console.log(Math.round(1/(scene.time - scene.prevTime)))
		scene.prevTime = scene.time

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
		scene.futPos += roadSecond*dir*2
		if scene.futPos > 1 || scene.futPos < 0
			scene.futPos -= dir

roadPosition = (scene) ->
	road = 1/scene.roadSecond
	pos = scene.futPos*road
	while pos >= 60
		pos -= 60

	pos = Math.round(pos)
	dir = scene.params.direction

	if dir == -1
		if (pos > 0 && pos < 8) ||  (pos > 30 && pos < 38)
			location = "straight"
		else if pos == 0 || pos == 30
			location = "approach"
		else if pos == 8 || pos == 38
			location = "exit"
		else
			location = "cornering"

		if pos >= 38 || pos < 8
			direction = "left"
		else
			direction = "right"

	if dir == 1
		if (pos > 0 && pos < 8) ||  (pos > 30 && pos < 38)
			location = "straight"
		else if pos == 8 || pos == 38
			location = "approach"
		else if pos == 0 || pos == 30
			location = "exit"
		else
			location = "cornering"

		if pos > 0 && pos <= 30
			direction = "right"
		else
			direction = "left"

	scene.player.roadPhase.direction = direction
	scene.player.roadPhase.phase = location



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

objectLoc = (object, x, y) ->
	aspect = window.innerWidth / window.innerHeight
	ratio = object.ratio
	w = aspect/ratio
	h = 1/ratio
	heigth = object.heigth
	object.position.x = (w*x - w/2) * heigth
	object.position.y = (h*y - h/2) * heigth

fixationCrossLoc = (scene, rev) ->
	aspect = window.innerWidth / window.innerHeight
	vFOV = scene.camera.fov/100
	hFOV = aspect*vFOV
	point2 = scene.predict[1]
	v2 = new THREE.Vector3(point2.y, 0.1, point2.x)
	v2.project(scene.camera)
	x2 = (v2.x+1)*0.5
	y2 =(v2.y+1)*0.5
	if rev == -1
		objectLoc scene.cross, x2 - 0.2/hFOV, y2
	else
		objectLoc scene.cross, x2 + 0.2/hFOV, y2

handleProbeLocs = (scene, n, rev, i) ->
	aspect = window.innerWidth / window.innerHeight
	vFOV = scene.camera.fov/100
	hFOV = aspect*vFOV
	p500 = scene.predict[0]
	p1000 = scene.predict[1]
	p2000 = scene.predict[2]
	p4000 = scene.predict[3]

	v1 = new THREE.Vector3(p500.y, 0, p500.x)
	v1.project(scene.camera)
	x1 = (v1.x+1)*0.5
	y1 =(v1.y+1)*0.5

	v2 = new THREE.Vector3(p1000.y, 0, p1000.x)
	v2.project(scene.camera)
	x2 = (v2.x+1)*0.5
	y2 =(v2.y+1)*0.5

	v3 = new THREE.Vector3(p2000.y, 0, p2000.x)
	v3.project(scene.camera)
	x3 = (v3.x+1)*0.5
	y3 =(v3.y+1)*0.5

	v4 = new THREE.Vector3(p4000.y, 0, p4000.x)
	v4.project(scene.camera)
	x4 = (v4.x+1)*0.5
	y4 =(v4.y+1)*0.5

	r = 0.075
	rx = r/hFOV
	ry = r/vFOV
	x = rx * Math.cos(Math.PI/4)
	y = ry * Math.sin(Math.PI/4)
	lis = [[x1, y1],[x2, y2],[x3, y3],[x4, y4]]
	xFix = lis[i][0]
	yFix = lis[i][1]
	pos = [[xFix - rx, yFix], [xFix + rx, yFix],  [xFix - x, yFix - y],[xFix + x, yFix - y]]
	for i from 0 til n
		objectLoc(scene.probes[i], pos[i][0],pos[i][1])
	objectLoc scene.cross, xFix, yFix

search = (scene) ->
	speed = scene.player.getSpeed()
	d = 0.01 / scene.centerLine.getLength()
	minC = 1000
	maxDist = speed*2/scene.centerLine.getLength()
	minPos = 0
	z = scene.player.physical.position.z
	x = scene.player.physical.position.x
	t = true
	for i from 0 til 8
		l = 0 + i*(1/8)
		r = 1/8 + i*(1/8)
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
	scene.player.posXY = scene.centerLine.getPointAt(minPos)
	return minPos

calculateFuture = (scene, r, speed) ->
	t1 = search(scene)
	fut = [0.5, 1, 2, 4, -0.1]
	for i from 0 til 5
		point = scene.centerLine.getPointAt(t1)
		dist = speed*fut[i]
		t2 = t1 + dist/scene.centerLine.getLength()*r
		if t2 >= 1
			t2 -= 1
		if t2 < 0
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
		speed = 80
if xrad === NaN
		xrad = ((80/3.6)*22 / Math.PI)
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

export basecircleDriving = seqr.bind (env, rx, ry, l, sky, ellipse) ->*
	env = env with
		controls: NonThrottleControl env.controls
	scene = yield circleScene env, rx, ry, l, sky, ellipse
	return scene

onInnerLane = (scene) ->
	pos = scene.centerLine.getPointAt(scene.player.pos)
	posActual = scene.player.physical.position
	c = ((posActual.z - pos.x) ^ 2 + (posActual.x - pos.y) ^ 2 ) ^ 0.5
	if c <= 1.75
		return true
	else
		return false

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

addFixationCross = (scene, c = 0x000000) ->
	vFOV = scene.camera.fov
	aspect = screen.width / screen.height
	angle = (vFOV/2) * Math.PI/180
	ratio = 2.75 / (vFOV)
	heigth = (Math.tan(angle) * 1000 * 2) * ratio
	size = heigth
	circleGeometry = new THREE.RingGeometry(size*0.95, size, 64)
	#horCross = new THREE.PlaneGeometry(size, size * 0.05)
	#verCross = new THREE.PlaneGeometry(size * 0.05, size)
	#horCross.merge(verCross)
	material = new THREE.MeshBasicMaterial color: c, transparent: true, depthTest: false, depthWrite: false
	crossMesh = new THREE.Mesh circleGeometry, material
	cross = new THREE.Object3D()
	cross.add crossMesh
	cross.position.z = -1000
	cross.heigth = heigth
	cross.ratio = ratio
	scene.camera.add cross
	scene.cross = cross
	objectLoc scene.cross, -0.1, -0.1
	cross.visible = true

markersVisible = (scene) ->
	for marker in scene.markers
		marker.visible = true


addBackgroundColor = (scene) ->
	geo = new THREE.PlaneGeometry 4000, 4000
	mat = new THREE.MeshBasicMaterial color: 0xd3d3d3, depthTest: false
	mesh = new THREE.Mesh geo, mat
	mesh.position.z = -1100
	scene.camera.add mesh

addMarkerScreen = (scene, env) ->
	aspect = screen.width / screen.height
	vFOV = scene.camera.fov
	angle = (vFOV/2) * Math.PI/180
	ratio = 0.1
	heigth = (Math.tan(angle) * 1000 * 2) * ratio
	scene.markers = []
	pos = [[0.5 0.8], [1 - 0.15/aspect, 0.8], [0.15/aspect, 0.1], [1 - 0.15/aspect, 0.1], [1 - 0.15/aspect, 0.1], [0.15/aspect, 0.8], [0.5, 0.8]]
	for i from 0 til 6
		path = 'res/markers/' + (i) + '_marker.png'
		texture = THREE.ImageUtils.loadTexture path
		marker = new THREE.Mesh do
			new THREE.PlaneGeometry heigth, heigth
			new THREE.MeshBasicMaterial map:texture, transparent: true, depthTest: false, depthWrite: false
		marker.position.z = -1000

		h = 1/ratio * heigth
		w = aspect * h
		marker.position.x = (w*(pos[i][0]) - w/2)
		marker.position.y = (h*pos[i][1] - h/2)
		scene.camera.add marker
		scene.markers.push marker
		marker.visible = true

listener = new THREE.AudioListener()
annoyingSound = new THREE.Audio(listener)
annoyingSound.load('res/sounds/beep-01a.wav')
annoyingSound.setVolume(0.5)

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

addBlinder = (scene, env) ->
	mask = new THREE.Mesh do
		new THREE.PlaneGeometry 0.1*16/9, 0.1
		new THREE.MeshBasicMaterial color: 0x000000
	mask.position.z = -0.3
	mask.position.x = 0.03
	mask.position.y = -0.03
	scene.camera.add mask

	self =
		change: Signal!
		glances: 0

	self._showMask = showMask = ->
		return if mask.visible
		mask.visible = true
		self.change.dispatch true
		env.logger.write blinder: true
	self._showMask()

	self._liftMask = ->
		mask.visible = false
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
	leader = yield addVehicle scene, leaderControls
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
		->
			@ \title .text L "Driving license"
			@ \text .append L "What class is your driver's licence?"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			input = $("""<input name="drivinglicenseclass" type="string" style="color: black">""")
			.appendTo @ \inputs
			setTimeout input~focus, 0
		->
			@ \title .text L "Driving license year"
			@ \text .append L "%intro.license"
			@ \accept .text L "Next"
			@ \cancel .text L "Previous"
			input = $("""<input name="drivinglicenseyear" type="number" min="1900" max="#currentYear" style="color: black">""")
			.appendTo @ \inputs
			setTimeout input~focus, 0
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
			@ \inputs .append radioSelect "gamingFreg",
				* value: 'daily', label: L "Most days"
				* value: 'weekly', label: L "Most weeks"
				* value: 'monthly', label: L "Most months"
				* value: 'yearly', label: L "Few times a year"
				* value: 'none', label: L "Not at all"
				* value: 'ex-player', label: L "I have played, but not anymore"
		->
			@ \title .text L "Driving games"
			@ \text .append L "Driving game history"
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


	#yield ui.inputDialog env, ->
	#	@ \title .text L "Welcome to the experiment"
	#	@ \text .text L "Please type your name."
	#	textbox = $('<input name="name" type="text" style="color: black">')
	#	.appendTo @ \content
	#	setTimeout textbox~focus, 0

exportScenario \experimentOutro, (env) ->*
	L = env.L
	yield ui.instructionScreen env, ->
		@ \title .append L "The experiment is done!"
		@ \content .append L '%experimentOutro'
		@ \accept-button .hide()
		@ \progress .hide()
		@ \progressTitle .hide()


exportScenario \calibration, (env, i) ->*
	L = env.L
	text = '%calib.inst' + i.toString()
	yield ui.instructionScreen env, ->
		@ \title .append L "Calibration"
		@ \content .append L text
		@ \accept .text L "Ready"
		@ \progress .hide()
		@ \progressTitle .hide()


exportScenario \blindPursuit, (env, {nTrials=50, oddballRate=0}={}) ->*
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

	catcher = new catchthething.Catchthething oddballRate: oddballRate

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

	catcher.objectCatched ->
		score.catched += 1
	catcher.objectMissed ->
		score.missed += 1


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



exportScenario \circle, (env, rx, s, dur) ->*

	if rx == undefined
		rx = xrad
	if s == undefined
		s = speed
	
	ry = rx
	aut = 0

	settingParams = {major_radius: rx, minor_radius: ry, straight_length: 0, target_speed: s, direction: 1, static_probes: 1, four: 1, future: 2, automatic: 0, deviant: 0}

	scene = yield basecircleDriving env, rx, ry, 0, true, false
	scene.params = settingParams
	addMarkerScreen scene, env

	startPoint = 0
	scene.player.physical.position.x = scene.centerLine.getPointAt(startPoint).y
	scene.player.physical.position.z = 0
	
	
	scene.playerControls.throttle = 0

	rw = scene.centerLine.width

	@let \scene, scene
	yield @get \run

	while not env.controls.catch == true
			yield P.delay 100
	env.controls.probeReact = false


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

		scene.prevTime = scene.time
		scene.player.prevSpeed = scene.player.getSpeed()*3.6

		if scene.end == true || (scene.time - startTime) > dur
			trialTime = scene.time - startTime
			listener.remove()
			@let \done, passed: true, outro:
				title: env.L "Passed"
				content: """
				<p>Suoritus kesti #{trialTime.toFixed 2} sekunttia.</p>
				 """
			return false

	return yield @get \done



exportScenario \circleRev, (env, rx, s, dur) ->*

	if rx == undefined
		rx = xrad
	if s == undefined
		s = speed
	
	ry = rx
	aut = 0

	settingParams = {major_radius: rx, minor_radius: ry, straight_length: 0, target_speed: s, direction: 1, static_probes: 1, four: 1, future: 2, automatic: 0, deviant: 0}

	scene = yield basecircleDriving env, rx, ry, 0, true, false
	scene.params = settingParams
	addMarkerScreen scene, env

	startPoint = 0
	scene.player.physical.position.x = scene.centerLine.getPointAt(startPoint).y*-1
	scene.player.physical.position.z = 0


	scene.playerControls.throttle = 0

	rw = scene.centerLine.width

	@let \scene, scene
	yield @get \run

	while not env.controls.catch == true
			yield P.delay 100
	env.controls.probeReact = false


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

		scene.prevTime = scene.time
		scene.player.prevSpeed = scene.player.getSpeed()*3.6

		if scene.end == true || (scene.time - startTime) > dur
			trialTime = scene.time - startTime
			listener.remove()
			@let \done, passed: true, outro:
				title: env.L "Passed"
				content: """
				<p>Suoritus kesti #{trialTime.toFixed 2} sekunttia.</p>
				 """
			return false

	return yield @get \done
