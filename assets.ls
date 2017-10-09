THREE = require 'three'
Cannon = require 'cannon'
$ = require 'jquery'
P = require 'bluebird'
seqr = require './seqr.ls'

require './node_modules/three/examples/js/SkyShader.js'

{loadCollada, mergeObject} = require './utils.ls'

svgToCanvas = seqr.bind (el, width, height, pw=0, ph=0) ->*
	img = new Image
	data = new Blob [el.outerHTML], type: 'image/svg+xml;charset=utf-8'
	p = new P (accept, reject) ->
		img.onload = accept
		img.onerror = reject
	DOMURL = window.URL ? window.webkitURL ? window;
	img.src = DOMURL.createObjectURL data
	yield p
	canvas = document.createElement 'canvas'
	canvas.width = width + pw
	canvas.height = height + ph

	ctx = canvas.getContext '2d'
	ctx.drawImage img, 0, 0, width, height
	DOMURL.revokeObjectURL img.src
	return canvas

svgToSign = seqr.bind (img, {pixelsPerMeter=100}={}) ->*
	texSize = (v) ->
		v = Math.round v*pixelsPerMeter
		return 0 if v < 1
		for i from 0 to Infinity
			pow2 = 2**i
			break if pow2 > v
		return [pow2, v - pow2]

	meters = (v) ->
		v = v.baseVal
		v.convertToSpecifiedUnits v.SVG_LENGTHTYPE_CM
		v.valueInSpecifiedUnits/100
	faceWidth = meters img.prop 'width'
	faceHeight = meters img.prop 'height'
	[w, pw] = texSize faceWidth
	[h, ph] = texSize faceHeight
	raster = yield svgToCanvas img[0], w, h, 0, 0 # TODO
	texture = new THREE.Texture raster
	texture.needsUpdate = true
	face = new THREE.Mesh do
		new THREE.PlaneGeometry faceWidth, faceHeight
		new THREE.MeshLambertMaterial do
			map: texture
			side: THREE.DoubleSide
			transparent: true
	face.width = faceWidth
	face.height = faceHeight
	return face

export SineGratingBitmap = ({resolution=1024, cycles=8}={}) ->
	canvas = document.createElement 'canvas'
	canvas.width = resolution
	canvas.height = resolution
	ctx = canvas.getContext '2d'
	img = ctx.createImageData resolution, resolution

	setPixel = (x, y, value, value2) ->
		i = (y*resolution + x)*4
		c = value*255
		c2 = value2*255
		img.data[i] = c
		img.data[i + 1] = c
		img.data[i + 2] = c
		img.data[i + 3] = c2

	for x til resolution
		for y til resolution
			rx = x/(resolution/2) - 1
			ry = y/(resolution/2) - 1
			d = Math.sqrt (rx**2 + ry**2)

			v = (Math.cos(rx*cycles*Math.PI) + 1)/2
			v2 = Math.cos d*Math.PI/2
			v2 *= d < 1.0
			setPixel x, y, v, v2
	ctx.putImageData img, 0, 0
	return canvas

SineGrating = (opts={}) ->
	canvas = SineGratingBitmap opts

	texture = new THREE.Texture canvas
	texture.needsUpdate = true
	face = new THREE.Mesh do
		new THREE.PlaneGeometry 1, 1
		new THREE.MeshLambertMaterial do
			map: texture
			side: THREE.DoubleSide
			transparent: true

	return face

export ArrowMarker = seqr.bind (opts={}) ->*
	#doc = $ yield $.ajax "./res/signs/arrow.svg", dataType: 'xml'
	marker = new THREE.Object3D
	marker.signs = signs = {}
	load = seqr.bind (name, file) ->*
		doc = $ yield $.ajax file, dataType: 'xml'
		img = $ doc.find "svg"
		obj = yield svgToSign img
		obj.visible = false
		marker.add obj
		signs[name] = obj

	marker.setSign = (name) ->
		for n, o of signs
			o.visible = false
		return if name not of signs
		signs[name].visible = true

	target = SineGrating opts
	target.visible = false
	target.transparent = true
	signs.target = target
	marker.add target

	marker.setFrequency = (frequency) ->
		return if frequency == target._frequency
		target.material.map = new THREE.Texture(SineGratingBitmap cycles: frequency)
		target.material.map.needsUpdate = true
		target.material.needsUpdate = true
		target._frequency = frequency

	yield load 'cue', './res/signs/arrow-circle.svg'
	yield load 'mask', './res/signs/arrow-mask.svg'
	yield load 'wait', './res/signs/arrow-wait.svg'
	yield load 'query', './res/signs/arrow-query.svg'
	yield load 'success', './res/signs/arrow-success.svg'
	yield load 'failure', './res/signs/arrow-failure.svg'

	return marker

export TrackingMarker = seqr.bind ->*
	#doc = $ yield $.ajax "./res/signs/arrow.svg", dataType: 'xml'
	doc = $ yield $.ajax "./res/signs/trackerbr.svg", dataType: 'xml'
	img = $ doc.find "svg"
	target = yield svgToSign img, pixelsPerMeter: 2000
	target.position.z = -2
	doc = $ yield $.ajax "./res/signs/trackerbar.svg", dataType: 'xml'
	img = $ doc.find "svg"
	crosshair = yield svgToSign img, pixelsPerMeter: 2000
	marker = new THREE.Object3D
	marker.add crosshair
	marker.add target
	marker.crosshair = crosshair
	marker.target = target
	return marker


export SpeedSign = seqr.bind (limit, {height=2, poleRadius=0.07/2}=opts={}) ->*
	doc = $ yield $.ajax "./res/signs/speedsign.svg", dataType: 'xml'
	img = $ doc.find "svg"
	(img.find '#limit')[0].textContent = limit

	sign = new THREE.Object3D
	face = yield svgToSign img, opts
	face.position.y = height
	face.position.z = -poleRadius - 0.01
	face.rotation.y = Math.PI
	sign.add face

	pole = new THREE.Mesh do
		new THREE.CylinderGeometry poleRadius, poleRadius, height, 32
		new THREE.MeshLambertMaterial color: 0xdddddd
	pole.position.y = height/2
	sign.add pole
	sign.traverse (o) ->
		o.castShadow = true
		o.receiveShadow = false
	return sign

export FinishSign = seqr.bind ({height=4, texSize=[256,256], poleRadius=0.07/2}=opts={}) ->*
	doc = $ yield $.ajax "./res/signs/finish.svg", dataType: 'xml'
	img = $ doc.find "svg"

	face = yield svgToSign img, opts
	sign = new THREE.Object3D
	face.position.y = height
	face.position.z = -poleRadius - 0.01
	face.rotation.y = Math.PI
	sign.add face

	pole = new THREE.Mesh do
		new THREE.CylinderGeometry poleRadius, poleRadius, height, 32
		new THREE.MeshLambertMaterial color: 0xdddddd
	pole.position.y = height/2
	pole.position.x = face.width/2
	sign.add pole
	pole = pole.clone()
	pole.position.x = -face.width/2
	sign.add pole
	sign.traverse (o) ->
		o.castShadow = true
		o.receiveShadow = false

	watcherWidth = face.width
	watcherHeight = height
	halfExtent = new Cannon.Vec3 watcherWidth/2, watcherHeight/2, 0.1
	watcherShape = new Cannon.Box halfExtent
	watcher = new Cannon.Body mass: 0, type: Cannon.Body.STATIC
		..addShape watcherShape, new Cannon.Vec3 0, watcherHeight/2, 0
		..objectClass = "finish-line"
		..collisionResponse = false
		..preventCollisionEvent = -> true



	self =
		onPassed: Signal!
		bodyPassed: (body) -> new Promise (accept) ->
			watcher.addEventListener "collide", (e) ->
				if e.body == body
					accept(e)
					return false

		visual: sign
		position: watcher.position
		addTo: (scene) ->
			scene.visual.add sign
			scene.physics.add watcher
			scene.bindPhys watcher, sign

	watcher.addEventListener "collide", (e) ->
		self.onPassed.dispatch e

	return self

export StopSign = seqr.bind ({height=2, poleRadius=0.07/2}=opts={}) ->*
	doc = $ yield $.ajax "./res/signs/stopsign.svg", dataType: 'xml'
	img = $ doc.find "svg"

	sign = new THREE.Object3D
	face = yield svgToSign img, opts
	face.position.y = height
	face.position.z = -poleRadius - 0.01
	face.rotation.y = Math.PI
	sign.add face

	pole = new THREE.Mesh do
		new THREE.CylinderGeometry poleRadius, poleRadius, height, 32
		new THREE.MeshLambertMaterial color: 0xdddddd
	pole.position.y = height/2
	sign.add pole

	watcherWidth = 5
	watcherHeight = 10
	halfExtent = new Cannon.Vec3 watcherWidth/2, watcherHeight/2, 0.1
	watcherShape = new Cannon.Box halfExtent
	watcher = new Cannon.Body mass: 0, type: Cannon.Body.STATIC
		..addShape watcherShape, halfExtent
		..objectClass = "stop-sign"
		..collisionResponse = false

	self =
		visual: sign
		position: watcher.position
		addTo: (scene) ->
			scene.visual.add sign
			scene.physics.add watcher
			scene.bindPhys watcher, sign

	return self

export BallBoard = seqr.bind ->*
	doc = $ yield $.ajax "./res/items/circle.svg", dataType: 'xml'
	img = $ doc.find "svg"
	ball = yield svgToSign img
	ball.scale.set 0.05, 0.05, 0.05
	ball.position.y = 0.05/2

	doc = $ yield $.ajax "./res/items/level.svg", dataType: 'xml'
	img = $ doc.find "svg"
	board = yield svgToSign img, pixelsPerMeter: 1000

	doc = $ yield $.ajax "./res/items/balancepoint.svg", dataType: 'xml'
	img = $ doc.find "svg"
	midpoint = yield svgToSign img, pixelsPerMeter: 1000

	obj = new THREE.Object3D
	obj.add midpoint

	turnable = new THREE.Object3D
	turnable.add ball
	obj.ball = ball
	turnable.add board

	obj.turnable = turnable
	obj.add turnable

	return obj

export ConstructionBarrel = seqr.bind ->*
	data = yield loadCollada 'res/signs/construction_barrel.dae'
	model = data.scene.children[0]
	model.scale.set 0.03, 0.03, 0.03

	bbox = new THREE.Box3().setFromObject model
	halfbox = new Cannon.Vec3().copy bbox.max.clone().sub(bbox.min).divideScalar 2
	phys = new Cannon.Body mass: 0
		..addShape (new Cannon.Box halfbox)
		..objectClass = 'barrier'

	addTo: (scene) ->
		scene.visual.add model
		scene.physics.add phys
		scene.bindPhys phys, model
	position: phys.position



export TrafficLight = seqr.bind ->*
	data = yield loadCollada 'res/signs/TrafficLight.dae'
	mod = data.scene.children[0]
	mod.scale.set 0.03, 0.03, 0.03
	mod.rotation.y = Math.PI
	mod.position.y -= 1.0
	model = new THREE.Object3D
		..add mod

	lights =
		red: model.getObjectByName 'Red'
		yellow: model.getObjectByName 'Yellow'
		green: model.getObjectByName 'Green'

	watcherWidth = 5
	watcherHeight = 10
	halfExtent = new Cannon.Vec3 5/2, 10/2, 0.1
	watcherShape = new Cannon.Box halfExtent
	watcher = new Cannon.Body mass: 0, type: Cannon.Body.STATIC
		..addShape watcherShape, halfExtent
		..objectClass = "traffic-light"
		..collisionResponse = false

	for let name, light of lights
		materials = light.children[0].material.materials
		materials = for material in materials
			material = material.clone()
			hsl = material.color.getHSL()
			material.color.setHSL hsl.h, hsl.s, 0.1
			material

		light.children[0].material.materials = materials

		light.on = ->
			for material in materials
				hsl = material.color.getHSL()
				material.emissive.setHSL hsl.h, 0.9, 0.5
			light.isOn = true

		light.off = ->
			for material in materials
				hsl = material.color.getHSL()
				material.emissive.setHSL hsl.h, 0.0, 0.0
			light.isOn = false

	onGreen = Signal!
	lights.red.on()
	#lights.yellow.on()
	#lights.green.on()
	getState: ->
		red: lights.red.isOn
		yellow: lights.yellow.isOn
		green: lights.green.isOn
	switchToGreen: seqr.bind ->*
		if lights.green.isOn
			lights.red.off()
			lights.yellow.off()
			return
		lights.red.on()
		lights.yellow.on()
		yield P.delay 1*1000
		lights.red.off()
		lights.yellow.off()
		lights.green.on()
		onGreen.dispatch()
	visual: model
	position: watcher.position
	addTo: (scene) ->
		scene.visual.add model
		scene.physics.add watcher
		scene.bindPhys watcher, model
		onGreen ->
			scene.physics.removeBody watcher

SunCalc = require 'suncalc'
export addSky = (scene, {location=[0, 0], date}={}) ->
	if not date?
		date = new Date 1970, 5, 24, 12

	distance = 40
	dome = new THREE.Object3D
	scene.visual.add dome
	sky = new THREE.Sky
	dome.add sky.mesh

	sunlight = new THREE.DirectionalLight 0xffffff, 0.5
		..castShadow = true
		..shadow.camera.near = distance/2
		..shadow.camera.far = distance*2
		..shadow.camera.left = -distance
		..shadow.camera.right = distance
		..shadow.camera.top = distance
		..shadow.camera.bottom = -distance
		..shadow.mapSize.width = 2048
		..shadow.mapSize.height = 2048
		..shadow.bias = 0.1
		..shadow.Darkness = 1.0
		..target = dome
		#
	scene.visual.add sunlight

	#hemiLight = new THREE.HemisphereLight 0xffffff, 0xffffff, 0.5
	#	..position.set 0, 4500, 0
	#scene.visual.add hemiLight
	scene.visual.add new THREE.AmbientLight 0xa0a0a0
	position = new THREE.Vector3
	scene.beforeRender.add ->
		#if sunlight.shadowCamera
		#	scene.camera = sunlight.shadowCamera
		position.setFromMatrixPosition scene.camera.matrixWorld
		dome.position.z = position.z
		dome.position.x = position.x
		sunlight.position.z = position.z
		sunlight.position.x = position.x

	updatePosition = ->
		degs = SunCalc.getPosition date, ...location

		position = new THREE.Vector3 0, 0, 4500
		position.applyEuler new THREE.Euler -degs.altitude, degs.azimuth, 0, "YXZ"
		sky.uniforms.sunPosition.value.copy position

		position = new THREE.Vector3 0, 0, distance
		position.applyEuler new THREE.Euler -degs.altitude, degs.azimuth, 0, "YXZ"
		sunlight.position.copy position

	updatePosition()
	setDate: (newDate) ->
		date := new Date newDate.getTime()
		updatePosition()
	getDate: -> new Date date.getTime()

export SceneDisplay = seqr.bind ({width=1024, height=1024}={}) ->*
	rtTexture = new THREE.WebGLRenderTarget width, height,
		minFilter: THREE.LinearFilter
		magFilter: THREE.NearestFilter
		format: THREE.RGBFormat

	geo = new THREE.PlaneGeometry 1, 1
	mat = new THREE.MeshBasicMaterial color: 0xffffff, map: rtTexture
	object = new THREE.Mesh geo, mat

	object: object
	renderTarget: rtTexture

export addMarkerScreen = (scene) ->
	aspect = screen.width / screen.height
	t = scene.camera.top
	b = scene.camera.bottom
	l = -aspect
	r = aspect
	s = 0.2
	pos = [[l + s, t - s], [r - s, t - s], [l + s, -t + s], [r - s, -t + s]]
	for i from 0 til 4
		path = 'res/markers/' + i + '_marker.png'
		texture = THREE.ImageUtils.loadTexture path
		marker = new THREE.Mesh do
			new THREE.PlaneGeometry s, s
			new THREE.MeshBasicMaterial map:texture
		marker.position.x = pos[i][0]
		marker.position.y = pos[i][1]
		scene.visual.add marker
