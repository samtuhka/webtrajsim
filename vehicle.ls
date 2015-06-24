P = require 'bluebird'
{PLoader} = require './ThreePromise.ls'

THREE = require 'three'
Cannon = require 'cannon'
{Signal} = require './signal.ls'

class DummyControls
	->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1

	set: ->



export addVehicle = (scene, controls=new DummyControls) ->
	P.props do
		body: (PLoader THREE.JSONLoader) 'res/camaro/blend/body.json'
		wheel: (PLoader THREE.JSONLoader) 'res/camaro/blend/wheel.json'
	.then ({body, wheel}) ->
		[o, m] = body
		[w, wm] = wheel

		syncModels = new Signal

		w.computeBoundingBox()
		wRadius = w.boundingBox.max.z
		wWidth = w.boundingBox.max.x*2

		o.computeBoundingBox()
		bbox = o.boundingBox
		bbox.min.y += 0.3
		halfbox = new Cannon.Vec3().copy bbox.max.clone().sub(bbox.min).divideScalar 2
		body = new THREE.Mesh o, (new THREE.MeshFaceMaterial m)
		scene.visual.add body

		offOrigin = new Cannon.Vec3().copy bbox.min.clone().add(bbox.max).divideScalar 2

		bodyPhys = new Cannon.Body mass: 2000
			..addShape (new Cannon.Box halfbox), offOrigin
			..linearDamping = 0.1
			..angularDamping = 0.1

		car = new Cannon.RaycastVehicle do
			chassisBody: bodyPhys
			indexRightAxis: 0
			indexForwardAxis: 2
			indexUpAxis: 1

		#controls = new MouseController $ 'body'

		enginePower = 6000
		brakePower = 100
		maxSteer = 0.8
		maxCentering = 0.4
		maxCenteringSpeed = 10
		steeringDeadzone = 0.005

		#ctrl.afterPhysics.add ->
		#	centering = (bodyPhys.velocity.norm()/maxCenteringSpeed)*maxCentering
		#	centering = Math.min centering, maxCentering
		#	controls.set autocenter: centering
		controls.set autocenter: 0.6


		wheelPositions = [
			[0.83, 0.0, 1.52],
			[-0.83, 0.0, 1.52],
			[0.83, 0.0, -1.45],
			[-0.83, 0.0, -1.45],
		]
		for let [x, y, z] in wheelPositions
			wii = car.addWheel do
				radius: wRadius
				directionLocal: new Cannon.Vec3 0, -1, 0
				axleLocal: new Cannon.Vec3 -1, 0, 0
				suspensionRestLength: wRadius + 0.25
				chassisConnectionPointLocal: new Cannon.Vec3(x, y, z).vadd offOrigin
				suspensionStiffness: 40
				rollInfluence: 1
				frictionSlip: 100
			wi = car.wheelInfos[wii]
			wheel = new THREE.Mesh w, new THREE.MeshFaceMaterial wm
			if x < 0
				tmp = new THREE.Object3D
				wheel.rotation.y = Math.PI
				tmp.add wheel
				wheel = tmp

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
					wi.brake = brakePower*controls.brake
					wi.steering = maxSteer*steering
				else
					# Back wheels
					wi.engineForce = -enginePower*controls.throttle*controls.direction

		syncModels.add ->
			body.position.copy bodyPhys.position
			# TODO: This may be wrong way around!
			body.quaternion.copy bodyPhys.quaternion

		scene.afterPhysics.add ->
			syncModels.dispatch()

		car.addToWorld scene.physics
		bodyPhys.position.y = 1

		eye = new THREE.Object3D
		eye.position.x = 0.4
		eye.position.y = 1.25
		eye.position.z = -0.1
		eye.rotation.y = Math.PI
		body.add eye

		eye: eye
		physical: bodyPhys
		body: body
		forceModelSync: -> syncModels.dispatch()


