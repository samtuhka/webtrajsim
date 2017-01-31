#!node_modules/.bin/lsc

global.Promise = require 'bluebird'
Promise.longStackTraces();

path = require "path"
Builder = require 'systemjs-builder'
System = require 'systemjs'
url = require 'url'

class URL
	(str) ->
		@ <<< url.parse(str.toString())

	toString: ->
		url.format @

global.URL = URL
require('system-npmlocator')(System)

builder = new Builder './'
require('./config.ls') builder
builder.buildStatic './ui-main.ls', './ui-main.ls.js'
