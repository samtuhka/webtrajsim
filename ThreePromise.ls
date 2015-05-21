Promise = require 'bluebird'

export PLoader = (LoaderCls) ->
	loader = new LoaderCls
	(...args) -> new Promise (resolve, reject) ->
		loader.load ...args, (...args) ->
			resolve args

