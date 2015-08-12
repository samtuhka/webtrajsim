P = require 'bluebird'
Co = P.coroutine
{PLoader} = require './ThreePromise.ls'

THREE = require 'three'
window.THREE = THREE
require './three.js/examples/js/loaders/ColladaLoader.js'
Cannon = require 'cannon'
{Signal} = require './signal.ls'

{loadCollada, mergeObject} = require './utils.ls'

class DummyControls
	->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1

	set: ->

loadCorolla = Co ->*
	vehicle = yield loadCollada 'res/corolla/body.dae'
	scene = vehicle.scene
	# Hack all materials double sided
	scene.traverse (obj) ->
		return if not obj.material?
		obj.material.side = THREE.DoubleSide
	body = scene.getObjectByName "Body"
	eye = new THREE.Object3D
	eye.position.y = 0.1
	eye.position.z = 0.3
	eye.rotation.y = Math.PI
	body.getObjectByName("DriverHeadrest").add eye
	body: body
	wheels: scene.getObjectByName "Wheels"
	eye: eye

loadViva = Co ->*
	vehicle = yield loadCollada "res/viva/2006-VIVA-VT3-Sedan-SE.dae"
	scene = vehicle.scene
	car = scene.getObjectByName "Car"

	centerXz = (obj) ->
		obj.updateMatrixWorld(true)
		bbox = (new THREE.Box3).setFromObject obj
		offcenter = bbox.max.add(bbox.min).divideScalar 2
		shift = offcenter.sub obj.position
		shift.y = 0
		obj.position.x = 0
		obj.position.z = 0
		for child in obj.children
			child.position.sub shift
		obj.updateMatrixWorld(true)

	originToGeometry = (obj) ->
		if obj.parent?
			obj.parent.updateMatrixWorld true
			obj.applyMatrix obj.parent.matrixWorld
			obj.parent = void
		obj.updateMatrixWorld(true)
		for child in obj.children
			child.applyMatrix obj.matrix
		obj.position.set 0, 0, 0
		obj.rotation.set 0, 0, 0
		obj.scale.set 1, 1, 1
		obj.updateMatrix()
		obj.updateMatrixWorld(true)

		bbox = (new THREE.Box3).setFromObject obj

		#w2l = (new THREE.Matrix4).getInverse(obj.matrixWorld)
		#bbox.min.applyMatrix4 w2l
		#bbox.max.applyMatrix4 w2l
		newOrigin = bbox.max.add(bbox.min).divideScalar 2
		currentPos = obj.position
		shift = newOrigin.clone().sub(currentPos)
		obj.position.copy newOrigin
		for child in obj.children
			child.position.sub shift
		obj.updateMatrixWorld(true)

	applyPosition = (obj) ->
		obj.updateMatrixWorld(true)
		pos = obj.position.clone()
		obj.position.set 0, 0, 0
		for child in obj.children
			child.position.add pos
		obj.updateMatrixWorld(true)

	centerXz car
	applyPosition car
	body = car.getObjectByName "Body"
	applyPosition body

	/*lights = []
	body.traverse (obj) ->
		return if obj.name != "Headlight"
		light = new THREE.SpotLight()
			..intensity = 0.5
			..angle = 40*(Math.PI/180)
			..distance = 10
			..exponent = 100
		target = new THREE.Object3D!
		position = (new THREE.Vector3).setFromMatrixPosition obj.matrixWorld
		console.log position
		target.position.z = 10
		target.position.y = -position.y
		target.position.x = 0
		light.add target
		light.target = target
		light.position.copy position
		lights.push light

	body.add ...lights*/
	body = mergeObject body
	eye = new THREE.Object3D
	eye.position.y = 1.23
	eye.position.z = 0.1
	eye.position.x = 0.37
	eye.rotation.y = Math.PI

	body.add eye
	wheels = scene.getObjectByName "Wheels"
	#applyPosition wheels
	for let wheel in wheels.children
		originToGeometry wheel
		wheel.position.y += 0.1
	body: body
	wheels: wheels
	eye: eye

export addVehicle = Co (scene, controls=new DummyControls, {objectName}={}) ->*
	{body, wheels, eye} = yield loadViva()

	syncModels = new Signal

	cogY = 0.5

	scene.visual.add body

	bbox = new THREE.Box3().setFromObject body
	bbox.min.y += 0.3
	halfbox = new Cannon.Vec3().copy bbox.max.clone().sub(bbox.min).divideScalar 2

	offOrigin = new Cannon.Vec3().copy bbox.min.clone().add(bbox.max).divideScalar 2
	offOrigin.y -= cogY

	bodyPhys = new Cannon.Body mass: 2000								# Vehicle mass
		..addShape (new Cannon.Box halfbox), offOrigin
		..linearDamping = 0.1									# "Air resistance"
		..angularDamping = 0.1
		..objectName = objectName
		..objectClass = 'vehicle'

	car = new Cannon.RaycastVehicle do
		chassisBody: bodyPhys
		indexRightAxis: 0
		indexForwardAxis: 2
		indexUpAxis: 1

	#controls = new MouseController $ 'body'

	enginePower = 6000										# Engine power
	brakePower = 1000										# Brake power
	brakeExponent = 2000										# Brake response
	brakeResponse = (pedal) -> (brakeExponent**pedal - 1)/brakeExponent*brakePower
	maxSteer = 0.8
	maxCentering = 0.4
	maxCenteringSpeed = 10
	steeringDeadzone = 0.005

	#ctrl.afterPhysics.add ->
	#	centering = (bodyPhys.velocity.norm()/maxCenteringSpeed)*maxCentering
	#	centering = Math.min centering, maxCentering
	#	controls.set autocenter: centering
	controls.set autocenter: 0.6


	wheels = wheels.children
	for let wheel in wheels
		wheel = wheel.clone()
		wbb = (new THREE.Box3).setFromObject wheel
		wRadius = (wbb.max.z - wbb.min.z)/2.0
		{x, y, z} = wheel.position
		wii = car.addWheel do
			radius: wRadius
			directionLocal: new Cannon.Vec3 0, -1, 0
			axleLocal: new Cannon.Vec3 -1, 0, 0
			suspensionRestLength: wRadius + 0.35
			chassisConnectionPointLocal: new Cannon.Vec3(x, y, z)
			suspensionStiffness: 40
			rollInfluence: 1
			frictionSlip: 1									# Wheel friction
		wi = car.wheelInfos[wii]
		#wheel = new THREE.Mesh w, new THREE.MeshFaceMaterial wm

		scene.visual.add wheel

		syncModels.add ->
			car.updateWheelTransform wii
			wheel.position.copy wi.worldTransform.position
			wheel.quaternion.copy wi.worldTransform.quaternion

		scene.beforePhysics.add ->
			mag = Math.abs controls.steering
			dir = Math.sign controls.steering
			mag -= steeringDeadzone
			mag = Math.max mag, 0
			steering = mag*dir*maxSteer
			if z > 0
				# Front wheels
				wi.brake = brakeResponse controls.brake
				wi.steering = maxSteer*steering
			else
				# Back wheels
				wi.engineForce = -enginePower*controls.throttle*controls.direction

	syncModels.add ->
		body.position.copy bodyPhys.position
		body.position.y -= cogY
		body.quaternion.copy bodyPhys.quaternion
		body.updateMatrixWorld()

	scene.afterPhysics.add ->
		syncModels.dispatch()

	car.addToWorld scene.physics
	scene.onExit ->
		car.removeFromWorld scene.physics
	bodyPhys.position.y = 2

	onCollision = Signal!
	bodyPhys.addEventListener "collide", (e) ->
		return if e.body.preventCollisionEvent? e
		onCollision.dispatch e

	getSpeed: ->
		return 0 if not car.currentVehicleSpeedKmHour?
		car.currentVehicleSpeedKmHour/3.6
	eye: eye
	physical: bodyPhys
	body: body
	forceModelSync: -> syncModels.dispatch()
	controls: controls
	onCollision: onCollision

