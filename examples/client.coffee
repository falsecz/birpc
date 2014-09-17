testRPC = require('../lib/index') "#{__dirname}/example.proto", 'TestRPC'
file = require('fs').readFileSync './occupy.png'
async = require 'async'
testRPC.connect 1234, 'localhost', (e, rpc) ->
	console.log rpc
	console.time 'x'
	async.times 1000, (i, next) ->
		rpc.test request: 12345, payload: file, next
	,(err) ->
		console.log err if err
		console.timeEnd 'x'
