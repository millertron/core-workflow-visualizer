# frozen_string_literal: true

require 'nokogiri'
require 'gviz'
require 'fileutils'
require './workflow_status'

if ARGV.empty?
  puts 'You must specify source XML file path'
  puts 'Usage: ruby single-workflow-parser.rb source_xml_file',
       ' [output_png_file_name]'
  exit
end

# Camelcasing used for status and action names
def camel_case(str)
  lower = str.downcase
  lower.tr(' ', '_').split('_').map(&:capitalize).join('')
end

# Read XML of path specified by the first argument
source_xml_file = ARGV[0]
source = Nokogiri::XML(File.open(source_xml_file))

# Load all workflow statuses and initialize them
status_path = '//workflow:workflowStatus'
workflow_statuses = source.xpath(status_path).map do |status_node|
  status_name = status_node.attr('name')
  WorkflowStatus.new(status_name)
end

# Populate workflow stasuses with actions and destination statuses
workflow_statuses.each do |status|
  action_path = "//workflow:workflowAction[@fromStatus='#{status.name}']"
  source.xpath(action_path).each do |action_node|
    action_name = action_node.attr('actionName')

    # find the first action component that executes a workflow change status
    workflow_change_component_xpath = "\
  		//workflow:actionComponentSequence[@actionName='#{action_name}']\
  		//child::*/workflow:component[@executorName='WORKFLOWCHANGESTATUS']"

    action_status_change = source.xpath(workflow_change_component_xpath).first

    # add action and the associate target status
    status.available_actions[action_name] = action_status_change
    &.attr('newStatusName')
  end
end

# Draw the flow diagram
Graph do
  global overlap: false
  nodes style: 'filled', color: 'green', shape: 'record'

  workflow_statuses.each do |status|
    # only create the node if it has any actions that change the status
    unless status.available_actions.empty?
      route camel_case(status.name) => status
        .available_actions
        .reject { |_action, target_status| target_status.nil? }
        .values
        .map { |target_status| camel_case(target_status) }
    end

    # label the arrows with the action name
    status.available_actions.each do |action, target_status|
      next unless target_status

      edge_name = "#{camel_case(status.name)}_#{camel_case(target_status)}"
      edges(arrowhead: 'onormal')
      edge(edge_name, label: camel_case(action))
    end
  end

  # generate output to specified or default path
  save(ARGV[1] || :output, :png)
end

# Move generated files to output directory
FileUtils.mkdir 'output' unless Dir.exist? 'output'
FileUtils.mv (Dir.glob('*.dot') + Dir.glob('*.png')), 'output'
