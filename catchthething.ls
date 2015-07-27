THREE = require "three"
$ = require 'jquery'
{jStat} = require 'jstat'
seqr = require './seqr.ls'
{Signal} = require './signal.ls'

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

export React = seqr.bind ({meanDelay=0.5, probeDuration=1, fadeOutDuration=0.2}={}) ->*
	self = {}

	self.event = Signal!
	self.camera = camera = new THREE.OrthographicCamera -1, 1, -1, 1, 0.1, 10
			..position.z = 5

	#camera.updateProjectionMatrix!
	#camera.updateMatrixWorld!
	#camera.matrixWorldInverse.getInverse @camera.matrixWorld
	#frustum = new THREE.Frustum
	#frustum.setFromMatrix(
	#	new THREE.Matrix4().multiplyMatrices @camera.projectionMatrix, @camera.matrixWorldInverse
	#)

	self.scene = scene = new THREE.Scene

	probeRadius = 0.05
	probe = new THREE.Mesh do
			new THREE.SphereGeometry probeRadius, 32, 32
			new THREE.MeshBasicMaterial color: 0xffffff, transparent: true
	probe.visible = false
	probe.active = false
	probe.timeLeft = 0
	probe.fadeLeft = 0
	self.scene.add probe
	self.score =
		catched: 0
		missed: 0
		fumbled: 0


	_readyForNew = (dt) ->
		return false if probe.visible
		Math.random() > Math.exp(-1/meanDelay * dt)

	randcoord = ->
		(Math.random() - 0.5)*2*0.8

	self.tick = (dt) ->
		if probe.active
			probe.timeLeft -= dt
			if probe.timeLeft <= 0
				self.score.missed += 1
				self.event.dispatch "missed"
				probe.visible = false
				probe.active = false
		else if probe.visible
			probe.fadeLeft -= dt
			if probe.fadeLeft <= 0
				probe.visible = false
			else
				stage = probe.fadeLeft/fadeOutDuration
				probe.material.opacity = stage
				scale = Math.min 100, 1.0/(stage)
				probe.scale.set scale, scale, scale

		if _readyForNew dt
			self.event.dispatch "show"
			probe.material.opacity = 1.0
			probe.scale.set 1.0, 1.0, 1.0
			probe.visible = true
			probe.active = true
			probe.position.x = randcoord!
			probe.position.y = randcoord!
			probe.timeLeft = probeDuration

	self.catch = ->
		if not probe.active
			self.event.dispatch "fumbled"
			self.score.fumbled += 1
			return
		self.event.dispatch "caught"
		self.score.catched += 1
		probe.active = false
		probe.fadeLeft = fadeOutDuration

	return self


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

