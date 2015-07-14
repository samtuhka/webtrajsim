THREE = require 'three'
window.THREE = THREE
require './three.js/examples/js/loaders/ColladaLoader.js'
P = require 'bluebird'

export loadCollada = (path) -> new P (resolve, reject) ->
	loader = new THREE.ColladaLoader
	loader.options.convertUpAxis = true
	loader.load path, resolve
