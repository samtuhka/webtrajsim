P = require 'bluebird'
Co = P.coroutine
{PLoader} = require './ThreePromise.ls'

THREE = require 'three'
window.THREE = THREE
require './node_modules/three/examples/js/loaders/ColladaLoader.js'
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

loadViva = Co (path) ->*
	vehicle = yield loadCollada path
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
			obj.parent = null
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

	checkMirrors = (obj) ->
		for material in obj.material.materials ? [obj.material]
			if material.name == 'MirrorCenter' || material.name == 'MirrorLeft' || material.name == 'MirrorRight'
				return true
		return false

	checkTransparent = (obj) ->
		for material in obj.material.materials ? [obj.material]
			if material.transparent == true
				return true
		return false
	steeringwheel = null
	body.traverse (obj) ->
		return if obj.name != "econo_sw"
		steeringwheel := obj.clone()
		position = obj.matrixWorld.getPosition()
		#steeringwheel.position.copy position
		#steeringwheel.position.z -= 0.1
		#steeringwheel.position.y += 0.15
		#steeringwheel.position.x += 0.02
		obj.parent.remove(obj)


	groupmaterial = new THREE.MultiMaterial()
	body.traverse (obj) ->
		return if not obj.material?
		for material in obj.material.materials ? [obj.material]
			if path == "res/viva/NPCViva.dae" #|| (checkTransparent(obj) == false && checkMirrors(obj) == false)
				material.transparent = false
				if material not in groupmaterial.materials
					groupmaterial.materials.push material
				obj.material = groupmaterial
				j = groupmaterial.materials.indexOf(material)
				for i from 0 til obj.geometry.faces.length
					obj.geometry.faces[i].materialIndex = j
					groupmaterial.materials[j].needsUpdate = true

	body = mergeObject body



	wheelmaterial = new THREE.MultiMaterial()
	if steeringwheel
		normals = []
		steeringwheel.traverse (obj) ->
			return if not obj.material?
			for material in obj.material.materials ? [obj.material]
				material.transparent = false

				obj.geometry.computeFaceNormals()
				obj.geometry.computeVertexNormals()
				normals.push(obj.geometry)
				if material not in wheelmaterial.materials
					wheelmaterial.materials.push material
				obj.material = wheelmaterial
				j = wheelmaterial.materials.indexOf(material)
				for i from 0 til obj.geometry.faces.length
					obj.geometry.faces[i].materialIndex = j
					wheelmaterial.materials[j].needsUpdate = true
		
		steeringwheel = mergeObject steeringwheel
		steeringwheel.normals = normals
		geometry = steeringwheel.children[0].geometry
		geometry.center()
		geometry.computeBoundingBox()
		max = geometry.boundingBox.max
		min = geometry.boundingBox.min
		steeringwheel.position.z = 0.58  - (max.z - min.z)*0.5
		steeringwheel.position.y = 0.95
		steeringwheel.position.x = 0.37


	body.add steeringwheel

	body.steeringwheel = steeringwheel

	body.traverse (obj) ->
		return if not obj.geometry?
		if path == "res/viva/NPCViva.dae"
			obj.geometry = new THREE.BufferGeometry().fromGeometry(obj.geometry)


	brakeLightMaterials = []
	body.traverse (obj) ->
		return if not obj.material?
		for material in obj.material.materials ? [obj.material]
			if material.name == 'Red'
				brakeLightMaterials.push material
	mirrors = []
	body.traverse (obj) ->
		return if not obj.material?
		if checkMirrors(obj)
			mirrors.push obj

	body.traverse (obj) ->
		return if not obj.material?
		for material in obj.material.materials ? [obj.material]
			if material.name == "Speedometer"
				body.tricycle = obj
	body.mirrors = mirrors

	eye = new THREE.Object3D
	eye.position.y = 1.23
	eye.position.z = 0.1
	eye.position.x = 0.37
	eye.rotation.y = Math.PI

	#eye.position.x += 10.0
	#eye.rotation.y -= Math.PI/2.0

	body.add eye
	wheels = scene.getObjectByName "Wheels"

	#applyPosition wheels
	for let wheel in wheels.children
		originToGeometry wheel
		wheel.position.y += 0.1
	geo = wheels.children[0].geometry
	mat = wheels.children[0].material
	for wheel in wheels.children
		wheel.geometry = geo
		wheel.material = mat
	body: body
	wheels: wheels
	eye: eye
	setBrakelight: (isOn) ->
		for material in brakeLightMaterials
			if isOn
				material.emissive.r = 200
			else
				material.emissive.r = 0
			material.needsUpdate = true

export addVehicle = Co (scene, controls=new DummyControls, path, {objectName, steeringNoise=-> 0.0}={}) ->*
	
	if not scene.viva
		{body, wheels, eye, setBrakelight} = yield loadViva(path)
		scene.viva = {body, wheels, eye, setBrakelight}
	else
		body = scene.viva.body.clone()
		wheels = scene.viva.wheels
		eye = scene.viva.eye.clone()
		setBrakelight = scene.viva.setBrakelight

	syncModels = new Signal

	cogY = 0.6

	visual = new THREE.Object3D()
	scene.visual.add visual
	visual.add body

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
	wheelModels = []
	for let wheel in wheels
		wheel = wheel.clone()
		wheelModels.push wheel
		wbb = (new THREE.Box3).setFromObject wheel
		wRadius = (wbb.max.z - wbb.min.z)/2.0
		{x, y, z} = wheel.position
		wii = car.addWheel do
			radius: wRadius
			directionLocal: new Cannon.Vec3 0, -1, 0
			axleLocal: new Cannon.Vec3 -1, 0, 0
			suspensionRestLength: wRadius + 0.35
			chassisConnectionPointLocal: new Cannon.Vec3(x, y, z)
			suspensionStiffness: 100
			rollInfluence: 1
			frictionSlip: 1									# Wheel friction
		wi = car.wheelInfos[wii]
		#wheel = new THREE.Mesh w, new THREE.MeshFaceMaterial wm

		visual.add wheel

		syncModels.add ->
			car.updateWheelTransform wii
			wheel.position.copy wi.worldTransform.position
			wheel.quaternion.copy wi.worldTransform.quaternion

		scene.beforePhysics.add (dt) ->
			#setBrakelight controls.brake > 0
			mag = Math.abs controls.steering
			dir = Math.sign controls.steering
			mag -= steeringDeadzone
			mag = Math.max mag, 0
			steering = mag*dir*maxSteer
			steering += steeringNoise dt
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
		return if e.body.preventCollisionEvent?
		onCollision.dispatch e

	getSpeed: ->
		if not car.currentVehicleSpeedKmHour? or not isFinite car.currentVehicleSpeedKmHour
			return 0.0
		car.currentVehicleSpeedKmHour/3.6
	eye: eye
	physical: bodyPhys
	body: body
	visual: visual
	wheels: wheelModels
	forceModelSync: -> syncModels.dispatch()
	controls: controls
	onCollision: onCollision

