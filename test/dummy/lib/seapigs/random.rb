require './config/environment.rb'

class ExecutionsLatest < Generator

	def self.handles?(object_id)
		object_id == 'random-list'
	end
	

	def self.generate(object_id)
		[{list: [1,2,3]}, 1]
	end

end
