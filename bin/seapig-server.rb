require 'websocket-eventmachine-server'
require 'json'
require 'set'
require 'jsondiff'

$workers = {}
$objects = {}
$pongs = {}

class SeapigObject

	attr_reader :id, :version
	attr_writer :worker

	
	def initialize(id, object, version, observers)
		@id = id
		@object = object
		@version = version
		@version_needed = nil
		@observers = observers
		@worker = nil #F support calculation of more than 1 version at the same time
		$objects[@id] = self
		@observers.each { |observer| observer.send self.json_diff(nil, {}) } if @version
		$objects.values.each { |object| object.check_validity } if @version
		self.gc
	end


	def gc
		return false if @observers.size > 0
		$objects.values.each { |object|
			return false if object.version.kind_of?(Hash) and object.version[@id]
		}
		$objects.delete(@id)
	end


	def link(socket)
		@observers << socket
	end


	def unlink(socket)
		@observers.delete(socket)
		gc
	end

	
	def to_hash
		{ id: @id, object: @object, version: @version }
	end
	

	def json_diff(old_version, old_object)
		 JSON.dump(
			action: 'patch',
			id: @id,
			old_version: old_version,
			new_version: @version,
			patch: JsonDiff.generate(old_object, @object)
		)

	end


	def update(object, version)
		old = to_hash
		@object = object
		@version = version
		@version_needed = @version if not @version_needed
		@observers.each { |observer|
			observer.send json_diff(old[:version],old[:object])
		}
		$objects.values.each { |object| object.check_validity }
	end


	def check_validity
		return true if @version and (not @version.kind_of?(Hash))
		version_needed = {}
		@version.each_pair { |dependency_id, dependency_version|
			version_needed[dependency_id] = $objects[dependency_id].version if $objects[dependency_id]
		} if @version
		#p :validity, self
		if (not @version) or (@version.size == version_needed.size and @version != version_needed and @version_needed != version_needed)
			@version_needed = version_needed if @version
			self.inquire($workers.values) if not @worker
		end
	end


	def inquire(workers)
		return if @version and (@version == @version_needed or @worker)
		workers.each { |worker|
			worker.inquire(self)
		}
	end


	def assign(worker)
		return if @version and (@version == @version_needed or @worker)		
		@worker = worker if worker.assign(self)
	end



	def inspect
		#'<SO:%s:%s:%s:%s>'%[@id,@version,@version_needed,@object.inspect]
		'<SO:%s:%s:%s>'%[@id,@version,@version_needed]
	end
	
end



class Worker

	def initialize(socket)
		@socket = socket
		@object = nil
	end
	

	def inquire(object)
		#p :busy, @object
		@socket.send JSON.dump(action: 'estimate', id: object.id) if not @object
	end


	def assign(object)
		return false if @object
		#p :assign, object
		@socket.send JSON.dump(action: 'generate', id: object.id)
		@object = object
	end


	def free
		#p :free, @object
		@object.worker = nil if @object
		@object = nil
	end


	def kill
		if @object
			@object.inquire($workers.values)
			self.free
		end
		$workers.delete(@socket)
	end

end





EM.run {


	WebSocket::EventMachine::Server.start(host: "0.0.0.0", port: 3001) { |client_socket|
		
		client_socket.onmessage { |message|
			$pongs[client_socket] = Time.new
			message = JSON.load message
			puts "Message: #{message['action']}"
			case message['action']
			when 'worker-register'
				$workers[client_socket] = worker = Worker.new(client_socket)
				$objects.values.each { |object| object.inquire([worker]) }
			when 'worker-estimate'
				object = $objects[message['id']]
				object.assign($workers[client_socket]) if object
			when 'update'
				$workers[client_socket].free if $workers[client_socket]
				if object = $objects[object_id = message['id']]
					object.update(message['object'], message['version'])
				else
					SeapigObject.new(object_id, message['object'], message['version'], Set.new) #.inquire($workers.values)
				end
				$objects.each_pair { |object_id, object| puts '- %25s: %s'%[object_id, object.inspect] }
			when 'link'
				if object = $objects[object_id = message['id']]
					object.link(client_socket)
					client_socket.send object.json_diff(nil, {})
				else
					SeapigObject.new(object_id, {}, nil, Set.new([client_socket])).inquire($workers.values)
				end
			when 'unlink'
				if object = $objects[object_id = message['id']]
					object.unlink(client_socket)
				end
			else
				p 'wtf', message['action']

			end
		}

		client_socket.onpong {
			$pongs[client_socket] = Time.new
		}
		
		client_socket.onclose {
			puts "Client disconnected"
			$pongs.delete(client_socket)
			$workers[client_socket].kill if $workers[client_socket]
			$objects.values.each { |object| object.unlink(client_socket) }
		}
	}

	
	EM.add_periodic_timer(10) {
		$pongs.keys.each { |client_socket|
			client_socket.ping
		}
	}


	EM.add_periodic_timer(10) {
		$pongs.each_pair { |client_socket, pong|
			client_socket.close if Time.new - pong > 60
		}
	}
	
}
