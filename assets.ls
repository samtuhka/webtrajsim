THREE = require 'three'
$ = require 'jquery'

P = require 'bluebird'
seqr = require './seqr.ls'

{loadCollada, mergeObject} = require './utils.ls'

svgToCanvas = seqr.bind (el, width, height) ->*
	img = new Image
	data = new Blob [el.outerHTML], type: 'image/svg+xml;charset=utf-8'
	p = new P (accept, reject) ->
		img.onload = accept
		img.onerror = reject
	DOMURL = window.URL ? window.webkitURL ? window;
	img.src = DOMURL.createObjectURL data
	yield p
	canvas = document.createElement 'canvas'
	canvas.width = width ?= el.width.baseVal.value
	canvas.height = height ?= el.height.baseVal.value

	ctx = canvas.getContext '2d'
	ctx.drawImage img, 0, 0, width, height
	DOMURL.revokeObjectURL img.src
	return canvas

export SpeedSign = seqr.bind (limit, {height=2, poleRadius=0.07/2, texSize=[256, 256]}={}) ->*
	doc = $ yield $.ajax "./res/signs/speedsign.svg"
	img = $ doc.get -1 # Damn

	meters = (v) ->
		v = v.baseVal
		v.convertToSpecifiedUnits v.SVG_LENGTHTYPE_CM
		v.valueInSpecifiedUnits/100
	img.find '#limit' .text limit
	faceWidth = meters img.prop 'width'
	faceHeight = meters img.prop 'height'

	raster = yield svgToCanvas img[0], ...texSize
	texture = new THREE.Texture raster
	texture.needsUpdate = true
	sign = new THREE.Object3D
	face = new THREE.Mesh do
		new THREE.PlaneGeometry faceWidth, faceHeight
		new THREE.MeshLambertMaterial do
			map: texture
			side: THREE.DoubleSide
			transparent: true
	face.position.y = height
	face.position.z = -poleRadius - 0.01
	face.rotation.y = Math.PI
	sign.add face

	pole = new THREE.Mesh do
		new THREE.CylinderGeometry poleRadius, poleRadius, height, 32
		new THREE.MeshLambertMaterial color: 0xdddddd
	pole.position.y = height/2
	sign.add pole
	return sign


export TrafficLight = seqr.bind ->*
	data = yield loadCollada 'res/signs/TrafficLight.dae'
	model = data.scene.children[0]
	model.scale.set 0.03, 0.03, 0.03

	lights =
		red: model.getObjectByName 'Red'
		yellow: model.getObjectByName 'Yellow'
		green: model.getObjectByName 'Green'

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


	visual: model
	addTo: (scene) ->
		scene.visual.add model


