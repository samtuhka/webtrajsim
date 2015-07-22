THREE = require 'three'
window.THREE = THREE
require './three.js/examples/js/loaders/ColladaLoader.js'
P = require 'bluebird'
{findIndex} = require 'prelude-ls'

export loadCollada = (path) -> new P (resolve, reject) ->
	loader = new THREE.ColladaLoader
	loader.options.convertUpAxis = true
	loader.load path, resolve

export mergeObject = (root) ->
	# TODO: Merge stuff using MeshFaceMaterials
	submeshes = new Map
	merged = new THREE.Object3D()

	getSubmesh = (object) ->
		key = object.material
		if submeshes.has key
			return submeshes.get key
		submesh = new THREE.Mesh (new THREE.Geometry), object.material.clone()
		submeshes.set key, submesh
		return submesh

	isTransparent = (o) ->
		return false if not o.material
		return true if o.material.transparent
		return false if not o.material.materials
		for material in o.material.materials
			return true if material.transparent
		return false

	merge = (object, matrix=(new THREE.Matrix4)) ->
		object.updateMatrix()
		# Don't merge transparent objects, 'cause rasterization
		# sucks
		if isTransparent object
			clone = object.clone()
			clone.applyMatrix matrix
			merged.add clone
			return
		matrix = matrix.clone().multiply object.matrix
		if object.geometry?
			getSubmesh(object).geometry.merge object.geometry, matrix
		for child in object.children
			merge child, matrix

	merge root
	submeshes.forEach (sub) ->
		merged.add sub
	merged.applyMatrix root.matrix
	return merged
