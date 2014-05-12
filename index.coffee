net = require 'net'
pbwire = require './pbwire'
wire = pbwire()
Proto = require 'protobufjs'
ByteBuffer = require 'protobufjs/node_modules/bytebuffer'


exports.connect = (port, host, protoFile, protoService, callback) ->
	client = net.connect port, host, () ->
		rpc = wire.handle protoFile, protoService, client
		callback rpc

exports.createServer = (protoFile, protoService, callback) ->
	net = require 'net'
	server = net.createServer (c) ->
		rpc = wire.handle protoFile, protoService, c, yes
		c.on 'connection-header', () ->
			callback rpc
	server


exports.Proto = Proto
exports.ByteBuffer = ByteBuffer