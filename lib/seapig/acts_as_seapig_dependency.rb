module SeapigDependency

	module ActsAsSeapigDependency

		extend ActiveSupport::Concern

		
		module ClassMethods
			
			def acts_as_seapig_dependency(options = {})

				self.instance_eval do

					def seapig_dependency_version
						self.find_by_sql('SELECT GREATEST(MAX(created_at), MAX(updated_at)) AS version FROM '+table_name).first.version.to_f
					end
					
					def seapig_dependency_changed(*tables)
						tables << self.name if tables.size == 0
						connection.instance_variable_get(:@connection).exec("NOTIFY seapig_dependency_changed,"+tables.map { |table| "'%s'"%[table] }.join(','))
					end
					
				end

			end
			
		end

	end

end
 

ActiveRecord::Base.send :include, SeapigDependency::ActsAsSeapigDependency
