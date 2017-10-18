Cannon = require 'cannon'
{Signal} = require './signal.ls'
jStat = require 'jstat'
P = require 'bluebird'
Co = P.coroutine
seqr = require './seqr.ls'
{loadCollada, mergeObject} = require './utils.ls'

perlin = require './vendor/perlin.js'

THREE = require 'three'

# TODO: Find a good fidelity/performance
# compromise parameters
export class Scene
	({@minStepDuration=1/60, @camera, @visual, @physics}={}) ->
		@ <<<
			beforePhysics: new Signal
			onPhysics: new Signal
			afterPhysics: new Signal

			beforeRender: new Signal
			onRender: new Signal
			afterRender: new Signal

			onTickHandled: new Signal

			onStart: new Signal
			onExit: new Signal

		@physics ?= new Cannon.World
			..gravity.set 0, -9.81, 0
			..defaultContactMaterial
				..friction = 0.7
				..restitution = 0.3
			..solver.iterations = 100
			..broadphase = new Cannon.SAPBroadphase @physics
		/*@physics =
			add: ->
			removeBody: ->
			addEventListener: ->
			step: ->
			bodies: []*/

		@visual ?= new THREE.Scene
		FOV = 70.0*(9/16)
		@camera ?= new THREE.PerspectiveCamera FOV, 1.6, 0.01, 450000

		@time = 0

		@onPhysics.add (dt) ~>
			nSteps = Math.ceil dt/@minStepDuration
			stepdur = dt/nSteps
			@physics.step stepdur, dt, nSteps

	tick: (dt) ->
		if dt == 0
			console.warn "BUG got dt of zero"
			return
		@beforePhysics.dispatch dt, @time
		@onPhysics.dispatch dt, @time
		@afterPhysics.dispatch dt, @time

		@beforeRender.dispatch dt, @time
		@onRender.dispatch dt, @time
		@afterRender.dispatch dt, @time

		@time += dt
		@onTickHandled.dispatch dt, @time


	bindPhys: (physical, visual) ->
		@afterPhysics.add ->
			visual.position.copy physical.position
			visual.quaternion.copy physical.quaternion

generateRock = (seed=Math.random()) ->
	perlin.seed seed
	radius = 1
	scale = radius
	noiseScale = 100
	geo = new THREE.IcosahedronGeometry radius, 1
	dir = new THREE.Vector3
	for vert in geo.vertices
		dir.copy vert
		dir.normalize()
		rnd = perlin.simplex3(vert.x*noiseScale, vert.y*noiseScale, vert.z*noiseScale)*scale
		dir.multiplyScalar Math.abs(rnd)*scale
		vert.add dir
	geo.verticesNeedUpdate = true
	geo.computeVertexNormals()
	geo.computeFaceNormals()
	rock = new THREE.Mesh geo, new THREE.MeshLambertMaterial do
		color: 0x696969
	rock.castShadow = true
	rock.receiveShadow = true
	return rock

export addGround = (scene) ->
	groundTex = THREE.ImageUtils.loadTexture 'res/world/sandtexture.jpg'
	terrainSize = 1000
	textureSize = 5
	textureRep = terrainSize/textureSize
	anisotropy = 16
	groundNorm = THREE.ImageUtils.loadTexture 'res/world/sandtexture.norm.jpg'
	groundTex.wrapS = groundTex.wrapT = THREE.RepeatWrapping
	groundNorm.wrapS = groundNorm.wrapT = THREE.RepeatWrapping
	groundTex.repeat.set textureRep, textureRep
	groundNorm.repeat.set textureRep, textureRep
	groundNorm.anisotropy = groundTex.anisotropy = anisotropy
	#groundNorm.minFilter = groundTex.minFilter = THREE.LinearFilter
	groundMaterial = new THREE.MeshPhongMaterial do
		color: 0xffffff
		map: groundTex
		#normalMap: groundNorm
		shininess: 20
	terrain = new THREE.Object3D
	terrain.receiveShadow = true
	groundGeometry = new THREE.PlaneGeometry terrainSize, terrainSize, 0, 0
	ground = new THREE.Mesh groundGeometry, groundMaterial
	ground.castShadow = false
	ground.receiveShadow = true
	ground.rotation.x = -Math.PI/2.0
	# To avoid z-fighting. Should be handled by
	# polygon offset, but it gives very weird results
	ground.position.y = -0.1
	groundBody = new Cannon.Body mass: 0
		..addShape new Cannon.Plane
		..quaternion.setFromAxisAngle new Cannon.Vec3(1,0,0), -Math.PI/2.0
	terrain.add ground
	scene.physics.add groundBody

	roadWidth = 7
	roadGeo = new THREE.PlaneGeometry terrainSize, roadWidth, 0, 0
	roadTex = THREE.ImageUtils.loadTexture 'res/world/road_texture.jpg'
	roadNorm = THREE.ImageUtils.loadTexture 'res/world/road_texture.norm.jpg'
	roadNorm.anisotropy = roadTex.anisotropy = anisotropy
	#roadTex.minFilter = THREE.LinearMipMapLinearFilter
	roadNorm.minFilter = roadTex.minFilter = THREE.LinearFilter
	roadTex.wrapS = roadTex.wrapT = THREE.RepeatWrapping
	roadNorm.wrapS = roadNorm.wrapT = THREE.RepeatWrapping
	roadTex.repeat.set textureRep/2.0, 1
	roadNorm.repeat.set textureRep/2.0, 1
	roadMat = new THREE.MeshPhongMaterial do
		map: roadTex
		shininess: 20
		normalMap: roadNorm
		shading: THREE.FlatShading
	road = new THREE.Mesh roadGeo, roadMat
	road.rotation.x = -Math.PI/2.0
	road.rotation.z = -Math.PI/2.0
	road.position.y = 0
	road.receiveShadow = true
	terrain.add road

	rocks = new THREE.Object3D()
	nRockTypes = 10
	rockPool = for i from 0 til nRockTypes
		generateRock()
	randomRock = ->
		rock = rockPool[Math.floor(Math.random()*rockPool.length)]
		return new THREE.Mesh rock.geometry, rock.material
	nRocks = Math.round(terrainSize*(2*200)/500)
	sizeDist = jStat.uniform(0.1, 0.6)
	zDist = jStat.uniform(-terrainSize/2, terrainSize/2)
	xDist = jStat.uniform(-200, 200)
	for i from 0 til nRocks
		x = xDist.sample()
		size = sizeDist.sample()
		if Math.abs(x) - Math.abs(size) < roadWidth
			continue
		z = zDist.sample()
		rock = randomRock()
		rock.position.x = x
		rock.position.z = z
		rock.scale.multiplyScalar size
		rock.scale.y *= 0.8
		rock.updateMatrix()
		rock.matrixAutoUpdate = false
		rocks.add rock

	terrain.add mergeObject rocks

	scene.visual.add terrain
	ahead = terrain.clone()
	behind = terrain.clone()
	scene.visual.add ahead
	scene.visual.add behind

	position = new THREE.Vector3
	scene.beforeRender.add ->
		position.setFromMatrixPosition scene.camera.matrixWorld
		nTerrains = Math.floor (position.z+terrainSize/2.0)/terrainSize
		terrain.position.z = nTerrains*terrainSize
		ahead.position.z = terrain.position.z + terrainSize
		behind.position.z = terrain.position.z - terrainSize

roadLoader = (k, terrainSize, turn, euler = false) ->
	x = require('./road_x.json') 
	y = require('./road_y.json')
	if euler 
		x = require('./road_euler_x.json') 
		y = require('./road_euler_y.json')
	vectors = []
	path = new THREE.CurvePath()
	for i from 0 til x.length - 1
		vec0 = new THREE.Vector3(y[i]*k*turn, x[i]*k - terrainSize, 0)
		vec1 = new THREE.Vector3(y[i + 1]*k*turn, x[i + 1]*k - terrainSize, 0)
		line = new THREE.LineCurve3(vec0, vec1)
		path.add(line)
	#path = new THREE.Path(vectors)
	#console.log path
	#dfdfdf
	return path
		
	 


export addCircleGround = (scene, rx, ry, length, hide, turn) ->
	groundTex = THREE.ImageUtils.loadTexture 'res/world/ground_moon.png'
	terrainSize = 800
	textureSize = 40
	textureRep = terrainSize/textureSize
	anisotropy = 8
	groundNorm = THREE.ImageUtils.loadTexture 'res/world/ground_moon_norm.png'
	groundTex.wrapS = groundTex.wrapT = THREE.RepeatWrapping
	groundNorm.wrapS = groundNorm.wrapT = THREE.RepeatWrapping
	groundTex.repeat.set textureRep, textureRep
	groundNorm.repeat.set textureRep, textureRep
	groundNorm.anisotropy = groundTex.anisotropy = anisotropy
	#groundNorm.minFilter = groundTex.minFilter = THREE.LinearFilter
	groundMaterial = new THREE.MeshBasicMaterial do
		color: 0x7F7F7F
		#map: groundTex
		#normalMap: groundNorm
		#shininess: 20
	terrain = new THREE.Object3D
	#terrain.receiveShadow = true
	groundGeometry = new THREE.PlaneGeometry terrainSize, terrainSize, 0, 0
	ground = new THREE.Mesh groundGeometry, groundMaterial
	#ground.castShadow = false
	#ground.receiveShadow = true
	ground.rotation.x = -Math.PI/2.0
	# To avoid z-fighting. Should be handled by
	# polygon offset, but it gives very weird results
	ground.position.y = -0.1
	groundBody = new Cannon.Body mass: 0
		..addShape new Cannon.Plane
		..quaternion.setFromAxisAngle new Cannon.Vec3(1,0,0), -Math.PI/2.0
	terrain.add ground
	scene.physics.add groundBody

	roadWidth = 3.5
	roadLenght = 4*roadWidth
	shape = new THREE.Shape()
	shape.moveTo(0, -0.5*roadWidth)
	shape.lineTo(0, 0.5*roadWidth)
	shape.lineTo(roadLenght, 0.5*roadWidth)
	shape.lineTo(roadLenght, -0.5*roadWidth)
	shape.lineTo(0, -0.5*roadWidth)

	generateCircle = (rX, rY, s) ->
		c = 0.5522847498307933984022516322796
		ox = rX * c
		oy = rY * c
		dy = -2*rX
		k = (terrainSize/2 - rX - 1.75)
		circle = new THREE.CurvePath()
		straight = new THREE.LineCurve3(new THREE.Vector3(-s, rX + k, 0), new THREE.Vector3(0, rX + k, 0))
		circle.add(straight)
		for i from 0 til 5
			curve1 = new THREE.CubicBezierCurve3(new THREE.Vector3(0, rX + k, 0), new THREE.Vector3(c*rY,rX + k, 0), new THREE.Vector3(rY, c*rX + k, 0), new THREE.Vector3(rY, 0 + k, 0))
			curve2 = new THREE.CubicBezierCurve3(new THREE.Vector3(rY, 0 + k, 0), new THREE.Vector3(rY, -c*rX + k, 0), new THREE.Vector3(c*rY, -rX + k, 0), new THREE.Vector3(0, -rX + k, 0))
			straight1 = new THREE.LineCurve3(new THREE.Vector3(0, -rX + k, 0), new THREE.Vector3(-s, -rX + k, 0))
			curveAlt = new THREE.CubicBezierCurve3(new THREE.Vector3(-s, -rX + k, 0), new THREE.Vector3(-s, -c*rX + k, 0), new THREE.Vector3(-c*rY - s, dy + k, 0), new THREE.Vector3(-rY - s, dy + k, 0))
			curve3 = new THREE.CubicBezierCurve3(new THREE.Vector3(-s, rX + dy + k, 0), new THREE.Vector3(-c*rY - s, rX + dy + k, 0),  new THREE.Vector3(-rY - s, c*rX + dy + k, 0), new THREE.Vector3(-rY - s, 0 + dy + k, 0))
			curve4 = new THREE.CubicBezierCurve3(new THREE.Vector3(-rY - s, 0 + dy + k, 0), new THREE.Vector3(-rY - s, -c*rX + dy + k, 0),  new THREE.Vector3(-c*rY - s, -rX + dy + k, 0), new THREE.Vector3(-s, -rX + dy + k, 0))
			straight2 = new THREE.LineCurve3(new THREE.Vector3(-s, rX + 2*dy + k, 0), new THREE.Vector3(0, rX + 2*dy + k, 0))
			circle.add(curve1)
			circle.add(curve2)
			circle.add(straight1)
			circle.add(curve3)
			circle.add(curve4)
			circle.add(straight2)
			k += 2*dy
		curve1 = new THREE.CubicBezierCurve3(new THREE.Vector3(0, rX + k, 0), new THREE.Vector3(c*rY,rX + k, 0), new THREE.Vector3(rY, c*rX + k, 0), new THREE.Vector3(rY, 0 + k, 0))
		curve2 = new THREE.CubicBezierCurve3(new THREE.Vector3(rY, 0 + k, 0), new THREE.Vector3(rY, -c*rX + k, 0), new THREE.Vector3(c*rY, -rX + k, 0), new THREE.Vector3(0, -rX + k, 0))
		straight1 = new THREE.LineCurve3(new THREE.Vector3(0, -rX + k, 0), new THREE.Vector3(-s, -rX + k, 0))
		circle.add(curve1)
		circle.add(curve2)
		circle.add(straight1)

		return circle

	deparam = require 'jquery-deparam'
	opts = deparam window.location.search.substring 1

	circle = roadLoader(rx, terrainSize, turn)


	scene.centerLine = circle #generateCircle(rx, ry, length)
	scene.centerLine.width = roadWidth
	extrudeSettings = {curveSegments: 10000, steps: 2500, bevelEnabled: false, extrudePath: circle}
	roadGeo = new THREE.ExtrudeGeometry shape, extrudeSettings
	roadTex = THREE.ImageUtils.loadTexture 'res/world/road_double.png'
	roadNorm = THREE.ImageUtils.loadTexture 'res/world/road_texture.norm.jpg'
	roadNorm.anisotropy = roadTex.anisotropy = anisotropy
	#roadTex.minFilter = THREE.LinearMipMapLinearFilter
	#roadNorm.minFilter = roadTex.minFilter = THREE.LinearFilter
	roadTex.minFilter = THREE.LinearMipMapLinearFilter
	roadTex.wrapS = roadTex.wrapT = THREE.RepeatWrapping
	roadNorm.wrapS = roadNorm.wrapT = THREE.RepeatWrapping
	#roadTex.repeat.set textureRep/2.0, 1
	#roadNorm.repeat.set textureRep/2.0, 1
	roadMat = new THREE.MeshPhongMaterial do
		#map: roadTex
		#shininess: 20
		#normalMap: roadNorm
		color: 0xffffff
		#transparent: true
		side: THREE.DoubleSide
		depthWrite: true
	#roadMat = new THREE.ShaderMaterial vertexShader: document.getElementById( 'vertexShader' ).textContent, fragmentShader: document.getElementById( 'fragmentShaderRoad' ).textContent, transparent: true
	#roadMat.polygonOffset = true
	#roadMat.depthTest = true
	#roadMat.polygonOffsetFactor = -1.0
	#roadMat.polygonOffsetUnits = -100.0

	faces = roadGeo.faces
	roadGeo.faceVertexUvs[0] = []
	r = 0

	circum = Math.round(circle.getLength() / (roadLenght))
	x = circum * 4 / (roadGeo.faces.length / 2)
	for i in [0 til roadGeo.faces.length/2 ]
		t = [new THREE.Vector2(r, 0), new THREE.Vector2(r, 1), new THREE.Vector2(r + x, 1), new THREE.Vector2(r + x, 0)]
		roadGeo.faceVertexUvs[0].push([t[0], t[1], t[3]])
		roadGeo.faceVertexUvs[0].push([t[1], t[2], t[3]])
		r += x
	roadGeo.uvsNeedUpdate = true
	road = new THREE.Mesh roadGeo, roadMat
	road.rotation.x = -Math.PI/2.0
	road.rotation.z = -Math.PI/2.0
	road.position.y = -0.09


	if hide
		road.visible = false
	#road.receiveShadow = true
	scene.road = road


	rocks = new THREE.Object3D()
	nRockTypes = 10
	rockPool = for i from 0 til nRockTypes
		generateRock()
	randomRock = ->
		rock = rockPool[Math.floor(Math.random()*rockPool.length)]
		return new THREE.Mesh rock.geometry, rock.material
	nRocks = Math.round(terrainSize*(2*200)/500)
	sizeDist = jStat.uniform(0.1, 0.6)
	zDist = jStat.uniform(-terrainSize/4, terrainSize/4)
	xDist = jStat.uniform(-terrainSize/2, terrainSize/2)
	rX = rx - 1
	rY = ry - 1
	for i from 0 til nRocks
		x = xDist.sample()
		size = sizeDist.sample()
		z = zDist.sample()
		cnt = false
		rW = roadWidth + 2
		xi = x - ((terrainSize/2 - rX - 1.75) - 500)
		if z <= 0 && z >= -length && xi < rx + rW && xi > rx - rW
				cnt = true
		for i from 0 til 6
			xi = x + i*rx*4 -((terrainSize/2 - rX - 1.75) - 500)
			if (((xi ^ 2 / ((rx + rW) ^ 2)  + (z ^ 2 / ((rY + rW) ^ 2))) <= 1)  && ((xi ^ 2 / ((rx - rW) ^ 2)  + (z ^ 2 / ((rY - rW) ^ 2))) > 1) && z >= 0)
				cnt = true
			if ((((xi - 2*rx) ^ 2 / ((rx + rW) ^ 2)  + ((z+length) ^ 2 / ((rY + rW) ^ 2))) <= 1)  && (((xi - 2*rx) ^ 2 / ((rx - rW) ^ 2)  + ((z+length) ^ 2 / ((rY - rW) ^ 2))) > 1) && z <= -length)
				cnt = true
			if z <= 0 && z >= -length && xi < -(rx*3 - rW) && xi > -(rx*3) - rW
				cnt = true
			if z <= 0 && z >= -length && xi < -(rx - rW) && xi > -rx - rW
				cnt = true
		if cnt == true
			continue
		rock = randomRock()
		rock.position.x = x
		rock.position.z = z
		rock.scale.multiplyScalar size
		rock.scale.y *= 0.8
		rock.updateMatrix()
		rock.matrixAutoUpdate = false
		rocks.add rock

	#terrain.add mergeObject rocks
	#terrain.visible= false


	left = terrain.clone()
	right = terrain.clone()
	left.position.x =  terrainSize
	right.position.x = -terrainSize
	terrain.add left
	terrain.add right

	scene.visual.add terrain



	ahead = terrain.clone()
	behind = terrain.clone()

	scene.visual.add road
	scene.visual.add ahead
	scene.visual.add behind





	position = new THREE.Vector3
	scene.beforeRender.add ->
		position.setFromMatrixPosition scene.camera.matrixWorld
		nTerrains = Math.floor (position.z+terrainSize/2.0)/terrainSize
		terrain.position.z = nTerrains*terrainSize
		ahead.position.z = terrain.position.z + terrainSize
		behind.position.z = terrain.position.z - terrainSize




