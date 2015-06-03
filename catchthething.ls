THREE = require "three"
$ = require 'jquery'
{jStat} = require 'jstat'

class TheThing
	->
		objectGeometry = new THREE.SphereGeometry 0.01, 32, 32
		objectMaterial = new THREE.MeshBasicMaterial color: 0xffffff
		@mesh = new THREE.Mesh objectGeometry, objectMaterial
		@mesh.position.set 1, 0, 0
		@velocity = new THREE.Vector3 -1, 0, 0
		@velocity.multiplyScalar Math.abs jStat.normal.sample(2, 0.5)

	tick: (dt) ->
		step = @velocity.clone().multiplyScalar dt
		@mesh.position.add step

export class Catchthething
	->
		@camera = new THREE.OrthographicCamera -1, 1, -1, 1, 0.1, 10
			..position.z = 5

		@camera.updateProjectionMatrix!
		@camera.updateMatrixWorld!
		@camera.matrixWorldInverse.getInverse @camera.matrixWorld
		@frustum = new THREE.Frustum
		@frustum.setFromMatrix(
			new THREE.Matrix4().multiplyMatrices @camera.projectionMatrix, @camera.matrixWorldInverse
		)

		@scene = new THREE.Scene

		radius = 0.1
		@target = new THREE.Sphere (new THREE.Vector3 -1+2*radius, 0, 0), radius

		@objects = []

		targetGeo = new THREE.SphereGeometry @target.radius, 32, 32
		targetMaterial = new THREE.MeshBasicMaterial do
			color: 0xffffff
			wireframe: true
		targetMesh = new THREE.Mesh targetGeo, targetMaterial
			..position.copy @target.center
		@scene.add targetMesh

		@meanDelay = 0.5

	_readyForNew: (dt) ->
		return false if @objects.length > 0
		Math.random() > Math.exp(-1/@meanDelay * dt)

	resize: (w, h) ->


	tick: (dt) ->
		if @_readyForNew dt
			thing = new TheThing
			@scene.add thing.mesh
			@objects.push thing

		prev = @objects
		@objects = []
		for thing in prev
			thing.tick dt
			if not @frustum.containsPoint thing.mesh.position
				@scene.remove thing.mesh
				continue
			@objects.push thing

	catch: ->
		misses = []
		for obj in @objects
			d = @target.distanceToPoint obj.mesh.position
			if d >= 0
				misses.push obj
				continue
			@scene.remove obj.mesh
		@objects = misses

