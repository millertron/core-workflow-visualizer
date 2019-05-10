# frozen_string_literal: true

require 'nokogiri'
require 'gviz'
require 'fileutils'
require './workflow_status'

if ARGV.empty?
  puts 'You must specify source XML file path'
  puts 'Usage: ruby multi-workflow-parser.rb source_xml_file'
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
client = source.xpath('//workflow:workflowConfigurationGroups').attr('client')

source.xpath('//workflow:workflowConfiguration').map do |actionable|
  actionable_type = actionable.attr('actionableType')

  # Load all workflow statuses and initialize them
  status_path = 'workflow:workflowStatuses/workflow:workflowStatus'
  workflow_statuses = actionable.xpath(status_path).map do |status_node|
    status_name = status_node.attr('name')
    WorkflowStatus.new(status_name)
  end

  # Populate workflow stasuses with actions and destination statuses
  workflow_statuses.each do |status|
    action_path = "workflow:workflowActions/\
      workflow:workflowAction[@fromStatus='#{status.name}']"
    actionable.xpath(action_path).each do |action_node|
      action_name = action_node.attr('actionName')

      # find the first action component that executes a workflow change status
      workflow_change_component_xpath = "\workflow:actionComponentSequences\
        /workflow:actionComponentSequence[@actionName='#{action_name}']\
        //child::*/workflow:component[@executorName='WORKFLOWCHANGESTATUS']"
      action_status_change = actionable.xpath(workflow_change_component_xpath)
      &.first

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
    save("#{client}_#{actionable_type}_workflow" || :output, :png)
  end
end

# Move generated files to output directory
FileUtils.mkdir 'output' unless Dir.exist? 'output'
client_directory = "output/#{client}"
FileUtils.mkdir client_directory unless Dir.exist? client_directory
FileUtils.mv (Dir.glob('*.dot') + Dir.glob('*.png')), client_directory
