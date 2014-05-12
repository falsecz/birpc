Proto = require 'protobufjs'
ByteBuffer = require 'protobufjs/node_modules/bytebuffer'
stream = require 'stream'
debug = require('debug') 'birpc'

{EventEmitter} = require 'events'

module.exports = () ->
	baseBuilder = Proto.loadProtoFile __dirname + '/birpc.proto'
	{Header, ErrorMessage} = baseBuilder.build()

	handle: (file, service, c, server=no) ->
		serviceBuilder = Proto.loadProtoFile file

		debug "Handling new connection"
		wasHeader = no
		calls = {}
		callId = 1

		c.on 'end', () ->
			debug "Client disconnected"

		c.writeInt = (i) ->
			v = new Buffer 4
			v.writeInt32BE i, 0
			c.write v

		c.writeWithLength = (b) ->
			c.writeInt b.length
			c.write b

		writeHeader = () ->
			v = new Buffer 1
			v.writeUInt8 0, 0

			a = new Buffer 1
			a.writeUInt8 0, 0
			header = Buffer.concat [new Buffer("BRPC"), v, a]
			c.write header


		unless server
			writeHeader()


		class Service extends EventEmitter
			constructor: (service, impl) ->
				r = serviceBuilder.lookup service
				throw new Error "Invalid service name: #{service}" unless r
				client = new r.clazz impl
				r.children.forEach (child) =>
					@[child.name] = (req, done) ->
						clazz = child.resolvedRequestType.clazz
						req = new clazz req if req not instanceof clazz
						client[child.name].call client, req, done

				@_handlers = {}
				@on 'request', (name, data, done) =>
					console.log name, @_handlers
					return unless @_handlers[name]

					@_handlers[name].forEach (item) ->
						console.log "jooo"
						item.call item, data, done


			handle: (name, callback) ->
				@_handlers[name] ?= []
				@_handlers[name].push callback

		getBufferDelimited = (b) ->
			len = ByteBuffer.calculateVarint32(b.length)
			ab = new ByteBuffer len
			ab.writeVarint32 b.length
			ab.append b

		impl = (method, req, callback) ->
			reflect = serviceBuilder.lookup method

			rh = new Header
				call_id: callId++
				method_name: reflect.name
				type: "REQUEST"

			calls[rh.call_id] =
				klazz: reflect.resolvedResponseType.clazz
				callback: callback

			a = getBufferDelimited rh.encode().toBuffer()
			a = a.append getBufferDelimited req.toBuffer()
			debug "r-->", JSON.stringify(rh), JSON.stringify(req), a.toBuffer().length + " bytes"

			c.writeInt a.toBuffer().length
			c.write a.toBuffer()

		buffer = new Buffer 0
		awaitBytes = 0

		c.on 'data', (data) ->
			if server and not wasHeader
				h = data.slice 0, 4
				unless h.toString().match "BRPC"
					debug 'Invalid header', h
					return c.end()
				debug 'Got connection header'
				wasHeader = yes
				c.emit 'connection-header'

			else
				buffer = Buffer.concat [buffer, data]

				return if awaitBytes is 0 and buffer.length < 4
				unless awaitBytes
					awaitBytes = buffer.readUInt32BE(0)
					buffer = buffer.slice 4
					debug "await", awaitBytes

				return if awaitBytes and buffer.length < awaitBytes

				processMessages buffer.slice 0, awaitBytes
				buffer = buffer.slice awaitBytes + 1
				awaitBytes = 0

		processMessages = (buffer) ->
				payload = ByteBuffer.wrap buffer
				readDelimited = () ->
					headerLen = payload.readVarint32()
					header = payload.slice payload.offset , payload.offset + headerLen
					payload.offset += headerLen
					# buffer = buffer.slice
					return header.toBuffer()

				h = Header.decode readDelimited()

				if h.type is Header.Type.REQUEST
					reflect = serviceBuilder.lookup  service + '.' + h.method_name
					p = readDelimited()
					rfl = reflect.resolvedRequestType.clazz.decode p
					debug "<---", JSON.stringify(h), JSON.stringify rfl
					svc.emit 'request', h.method_name, rfl, (err, data) ->
						if err
							rh = new Header
								call_id: h.call_id
								type: "RESPONSE"
								error:
									message: err?.message or err

							a = getBufferDelimited rh.encode()
							debug "--->", JSON.stringify(rh), a.toBuffer().length + " bytes"

							c.writeInt a.toBuffer().length
							c.write a.toBuffer()

							return

						o = new reflect.resolvedResponseType.clazz data
						pl = o.encode()


						rh = new Header
							call_id: h.call_id
							type: "RESPONSE"

						debug "Response", JSON.stringify rh

						a = getBufferDelimited rh.encode().toBuffer()
						a = a.append getBufferDelimited pl.toBuffer()

						c.writeInt a.toBuffer().length
						c.write a.toBuffer()

				else
					currentCall = calls[h.call_id]
					unless currentCall
						return debug "Call #{h.call_id} not found!"
					delete calls[h.call_id]
					err = undefined
					response = undefined
					if h.error
						err = h.error
						debug "<---", JSON.stringify(h)
					else
						response = currentCall.klazz.decode readDelimited()
						debug "<---", JSON.stringify(h), response

					currentCall.callback?.call currentCall.callback, err, response


		svc = new Service service, impl
		svc.builder = serviceBuilder.result
		return svc


