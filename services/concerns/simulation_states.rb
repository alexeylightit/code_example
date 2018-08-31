# frozen_string_literal: true

# Simulation state machine
module SimulationStates
  extend ActiveSupport::Concern

  included do
    attr_reader :state

    state_machine initial: :created, action: :save do
      transition created: :deploying, on: :start
      transition deploying: :ready, on: :idle
      transition ready: :downloading, on: :download
      transition downloading: :processing, on: :process
      transition processing: :rendering, on: :render
      transition rendering: :collecting, on: :upload
      transition collecting: :finished, on: :finish
      transition any - %i[finished failed stopped] => :stopped, on: :stop
      transition any - %i[finished failed stopped] => :failed, on: :error
      transition %i[stopped failed] => :deploying, on: :restart
    end
  end

  def continue!
    perform state_events.first
  end

  def perform(action)
    action = action.to_sym
    perform_action action
  rescue StandardError => e
    @errors << e.message
    false
  end

  private

  def perform_action(action)
    raise IncorrectEvent, action unless state_events.include? action
    fire_state_event(action)
  end

  # Error class for incorrect events
  class IncorrectEvent < StandardError
    def initialize(msg)
      super "Invalid action: #{msg}."
    end
  end

end
