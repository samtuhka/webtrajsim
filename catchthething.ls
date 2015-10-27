THREE = require "three"
$ = require 'jquery'
jStat = require 'jstat'
seqr = require './seqr.ls'
{Signal} = require './signal.ls'

class AngledThing
	({@oddballRate=0, @angle, @totalHeight=1.0}={}) ->
		@rndpos = ~> (Math.random! - 0.5)*@totalHeight
		@targetY = @rndpos!
		@originY = @rndpos!
		objectGeometry = new THREE.SphereGeometry 0.01, 32, 32
		objectMaterial = new THREE.MeshBasicMaterial color: 0xffffff
		@mesh = new THREE.Mesh objectGeometry, objectMaterial
		@mesh.position.set 1, 0, 0
		@velocity = -1.5
		#@velocity.multiplyScalar Math.abs jStat.normal.sample(2, 0.5)
		@manipulated = false
		@t = 0

	tick: (dt) ->
		@t += dt
		#step = @velocity.clone().multiplyScalar dt
		#@mesh.position.add step
		prevPos = @mesh.position.clone()
		x0 = 1
		x1 = -0.5
		total = (x0 - x1)
		d = Math.abs(@velocity*@t)
		@mesh.position.x = x = @velocity*@t + x0
		relx = d/total
		@mesh.position.y = (1 - relx)*@originY + relx*@targetY

		if prevPos.x > 0 and @mesh.position.x < 0 and (not @manipulated) and (Math.random() < @oddballRate)
			manip = Math.sign(Math.random() - 0.5)*0.05
			console.log manip
			@manipulated = true
			@targetY += manip
			@originY += manip



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

export class SpatialCatch
	({@oddballRate=0.0, @controls}={}) ->
		@objectHandled = Signal()
		@objectCatched = Signal()
		@objectMissed = Signal()

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


		targetWidth = 0.03
		targetHeight = @targetHeight = 0.5
		@targetX = -0.5

		@inactiveOpacity = 0.3
		@activeOpacity = 1.0
		@topTarget = new THREE.Mesh do
			new THREE.PlaneGeometry targetWidth, targetHeight
			new THREE.MeshBasicMaterial do
				color: 0xffffff
				opacity: @inactiveOpacity
				transparent: true
		@topTarget.rotation.y = -Math.PI
		@topTarget.position.y = -targetHeight/2.0
		@topTarget.position.x = @targetX
		@scene.add @topTarget

		@bottomTarget = new THREE.Mesh do
			new THREE.PlaneGeometry targetWidth, targetHeight
			new THREE.MeshBasicMaterial do
				color: 0xffffff
				opacity: @inactiveOpacity
				transparent: true
		@bottomTarget.rotation.y = -Math.PI
		@bottomTarget.position.y = targetHeight/2.0
		@bottomTarget.position.x = @targetX
		@scene.add @bottomTarget

		maskWidth = 0.3
		@mask = new THREE.Mesh do
			new THREE.PlaneGeometry maskWidth, targetHeight*2
			new THREE.MeshBasicMaterial do
				color: 0x000000
		@mask.rotation.y = -Math.PI
		@scene.add @mask

		@meanDelay = 1.0
		@objects = []

	_readyForNew: (dt) ->
		return false if @objects.length > 0
		Math.random() > Math.exp(-1/@meanDelay * dt)

	tick: (dt) ->
		if @_readyForNew dt
			thing = new AngledThing do
				oddballRate: @oddballRate
				totalHeight: 0.3
			@scene.add thing.mesh
			@objects.push thing

		@topTarget.material.opacity = @inactiveOpacity
		@bottomTarget.material.opacity = @inactiveOpacity
		if @controls.up and not @controls.down
			@topTarget.material.opacity = @activeOpacity
		if @controls.down and not @controls.up
			@bottomTarget.material.opacity = @activeOpacity

		prev = @objects
		@objects = []
		for thing in prev
			prevX = thing.mesh.position.x
			thing.tick dt
			if prevX > @targetX and thing.mesh.position.x < @targetX
				y = thing.mesh.position.y
				caught = y < 0 and @controls.up
				caught = caught or y > 0 and @controls.down
				caught = caught and not (@controls.up and @controls.down)
				if caught
					@objectHandled.dispatch thing
					@objectCatched.dispatch thing
					@scene.remove thing.mesh
					continue

			if not @frustum.containsPoint thing.mesh.position
				@scene.remove thing.mesh
				@objectMissed.dispatch thing
				@objectHandled.dispatch thing
				continue
			@objects.push thing


class BallisticThing
	({@oddballRate=0}={}) ->
		objectGeometry = new THREE.SphereGeometry 0.01, 32, 32
		objectMaterial = new THREE.MeshBasicMaterial color: 0xffffff
		@mesh = new THREE.Mesh objectGeometry, objectMaterial
		@mesh.position.set 1, 0, 0
		@velocity = -1.5
		#@velocity.multiplyScalar Math.abs jStat.normal.sample(2, 0.5)
		@manipulated = false
		@t = 0

	tick: (dt) ->
		@t += dt
		#step = @velocity.clone().multiplyScalar dt
		#@mesh.position.add step
		prevPos = @mesh.position.clone()
		x0 = 1
		x1 = -0.5
		@mesh.position.x = x = @velocity*@t + x0

		total = (x0 - x1)
		h = -0.3
		y0 = 0
		d = Math.abs(@velocity*@t)

		a = -4*(h - y0)/(total**2)
		b = 4*(h - y0)/total
		@mesh.position.y = y0 + a*d**2 + b*d

		# Hack!
		if prevPos.x > 0 and @mesh.position.x < 0 and (not @manipulated) and (Math.random() < @oddballRate)
			manip = Math.sign((Math.random() - 0.5)*2)*0.1
			@t += manip
			@manipulated = true



export class Catchthething
	({@oddballRate=0}={}) ->
		@objectHandled = Signal()
		@objectCatched = Signal()
		@objectMissed = Signal()

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

		radius = 0.15
		@target = new THREE.Sphere (new THREE.Vector3 0, 0, 0), radius

		@objects = []

		targetGeo = new THREE.SphereGeometry @target.radius, 32, 32
		targetMaterial = new THREE.MeshBasicMaterial do
			color: 0xffffff
			wireframe: true
		targetMesh = new THREE.Mesh targetGeo, targetMaterial
		@scene.add targetMesh
		@targetMesh = targetMesh
		@targetMesh.position.x = -0.5

		mask = new THREE.Mesh do
			new THREE.PlaneGeometry 0.3, 0.3
			new THREE.MeshBasicMaterial color: 0xffffff
		mask.position.z = -1
		mask.position.y = -0.3
		mask.rotation.x = Math.PI
		@scene.add mask

		@meanDelay = 1

	_readyForNew: (dt) ->
		return false if @objects.length > 0
		Math.random() > Math.exp(-1/@meanDelay * dt)

	resize: (w, h) ->


	tick: (dt) ->
		if @_readyForNew dt
			thing = new BallisticThing oddballRate: @oddballRate
			@scene.add thing.mesh
			@objects.push thing

		prev = @objects
		@objects = []
		for thing in prev
			thing.tick dt
			if not @frustum.containsPoint thing.mesh.position
				@scene.remove thing.mesh
				@objectHandled.dispatch thing
				@objectMissed.dispatch thing
				continue
			@objects.push thing

	catch: ->
		misses = []
		for obj in @objects
			d = @targetMesh.position.distanceTo obj.mesh.position
			if d >= @target.radius
				misses.push obj
				continue
			@scene.remove obj.mesh
			@objectHandled.dispatch obj
			@objectCatched.dispatch obj
		@objects = misses

