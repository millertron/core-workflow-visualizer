# Individual Workflow status node to be rendered
class WorkflowStatus
  attr_reader :name, :available_actions

  def initialize(name)
    @name = name
    @available_actions = {}
  end


end
