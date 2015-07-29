$ = require 'jquery'
deparam = require 'jquery-deparam'
experiments = require './experiments.ls'
seqr = require './seqr.ls'

$ seqr.bind !->*
	opts = deparam window.location.search.substring 1
	experimentName = opts.experiment ? \defaultExperiment
	experiment = experiments[experimentName]
	yield experiment()
