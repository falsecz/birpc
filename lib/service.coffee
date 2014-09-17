module.exports = (service, rpcImpl) ->

	calls = {}
	callCount = 0
	handlers = {}

	client = new service.clazz rpcImpl

	out = {}

	service.children.forEach (child) ->
		out[child.name] = (req, done) ->
			clazz = child.resolvedRequestType.clazz
			req = new clazz req unless req instanceof clazz
			client[child.name].call client, req, done

	out.handle = (name, callback) ->
		handlers[name] = callback
