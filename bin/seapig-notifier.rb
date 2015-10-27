require './config/environment.rb'

require 'websocket-eventmachine-client'
require 'json'


Rails.application.eager_load!
notifiers = Hash[*ActiveRecord::Base.descendants.select { |cls| cls.respond_to?('seapig_dependency_version') }.map { |notifier| [notifier.name,notifier] }.flatten ]

$last_versions = {}
$payloads = Queue.new

EM.run {

	socket = WebSocket::EventMachine::Client.connect(uri: ARGV[0])

	
	on_database_change = Proc.new {
		payloads = Set.new
		payloads << $payloads.pop while not $payloads.empty?
		payloads.each { |notifier_name|
			version = notifiers[notifier_name].seapig_dependency_version #F handle wrong names
			if $last_versions[notifier_name] != version	
				socket.send(JSON.dump(action: 'update', id: notifier_name, version: version))
				$last_versions[notifier_name] = version
			end
		}
	}


	socket.onopen {
		socket.send JSON.dump(action: 'worker-register')
		Thread.new {
			ActiveRecord::Base.connection_pool.with_connection { |connection|
				connection = connection.instance_variable_get(:@connection)
				connection.exec("LISTEN seapig_dependency_changed")
				loop {
					connection.wait_for_notify { |channel, pid, payload|
						$payloads << payload
						EM.schedule(on_database_change)
					}
				}
			}
		}
		EM.schedule on_database_change
	}

	
	socket.onclose { |code, reason|
		EM.stop
	}

}

	
