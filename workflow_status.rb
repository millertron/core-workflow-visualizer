class WorkflowStatus
	attr_reader :name, :available_actions

	def initialize(name)
		@name = name
		@available_actions = Hash.new
	end
end
