Cannon = require 'cannon'
{Signal} = require 'signals'

# Todo: ugly
window.THREE = THREE = require 'three'
require 'script!./three.js/examples/js/SkyShader.js'

export class Scene
	({@stepDuration=1/60}={}) ->
		@physics = new Cannon.World
			..gravity.set 0, -9.81, 0
			..defaultContactMaterial
				..friction = 10
				..restitution = 0.3
			..solver.iterations = 10
			..broadphase = new Cannon.SAPBroadphase @physics

		@visual = new THREE.Scene

		@camera = new THREE.PerspectiveCamera 50, 1, 0.01, 450000

		@onPhysics.add (dt) ~>
			@physics.step @stepDuration, dt

	tick: (dt) ->
		@beforePhysics.dispatch dt
		@onPhysics.dispatch dt
		@afterPhysics.dispatch dt
		
		@beforeRender.dispatch dt
		@onRender.dispatch dt
		@afterRender.dispatch dt

	beforePhysics: new Signal
	onPhysics: new Signal
	afterPhysics: new Signal
	
	beforeRender: new Signal
	onRender: new Signal
	afterRender: new Signal

	bindPhys: (physical, visual) ->
		@afterPhysics.add ->
			visual.position.copy physical.position
			visual.quaternion.copy physical.quaternion

export addSky = (scene) ->
	sky = new THREE.Sky
	sky.uniforms.sunPosition.value.y = 400
	scene.visual.add sky.mesh

	sunlight = new THREE.DirectionalLight 0xffffff, 0.5
	sunlight.position.set 0, 1, 0
	scene.visual.add sunlight
	hemiLight = new THREE.HemisphereLight 0xffffff, 0xffffff, 0.3
		..position.set 0, 4500, 0
	scene.visual.add hemiLight

export addGround = (scene) ->
	groundTex = THREE.ImageUtils.loadTexture 'res/world/sandtexture.jpg'
	terrainSize = 10000
	textureSize = 5
	textureRep = terrainSize/textureSize
	groundNorm = THREE.ImageUtils.loadTexture 'res/world/sandtexture.norm.jpg'
	groundTex.wrapS = groundTex.wrapT = THREE.RepeatWrapping
	groundNorm.wrapS = groundNorm.wrapT = THREE.RepeatWrapping
	groundTex.repeat.set textureRep, textureRep
	groundNorm.repeat.set textureRep, textureRep
	groundTex.anisotropy = 12 #renderer.getMaxAnisotropy()
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
	scene.visual.add ground
	scene.physics.add groundBody

	roadWidth = 10
	roadGeo = new THREE.PlaneGeometry terrainSize, roadWidth, 0, 0
	roadTex = THREE.ImageUtils.loadTexture 'res/world/road_texture.jpg'
	roadNorm = THREE.ImageUtils.loadTexture 'res/world/road_texture.norm.jpg'
	roadTex.anisotropy = 12#renderer.getMaxAnisotropy()
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
	scene.visual.add road

