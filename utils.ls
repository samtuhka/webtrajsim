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
	submeshes = new Map

	getSubmesh = (object) ->
		key = object.material
		if submeshes.has key
			return submeshes.get key
		submesh = new THREE.Mesh (new THREE.Geometry), object.material.clone()
		submeshes.set key, submesh
		return submesh

	merge = (object, matrix=(new THREE.Matrix4)) ->
		object.updateMatrix()
		matrix = matrix.clone().multiply object.matrix
		if object.geometry?
			getSubmesh(object).geometry.merge object.geometry, matrix
		for child in object.children
			merge child, matrix

	merge root
	merged = new THREE.Object3D()
	submeshes.forEach (sub) ->
		merged.add sub
	merged.applyMatrix root.matrix
	return merged
