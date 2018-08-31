# frozen_string_literal: true

# ProjectForm factory
module ProjectForm
  # Base class includes basic form logic
  class Factory < Reform::Form
    include Events

    model :project
    property :state

    delegate :name, to: :model
    delegate_missing_to :simulation_model

    # Load particular form with validations
    def build(step)
      step = default_step if step.blank?
      form_name = "ProjectForm::#{step.capitalize}Form".constantize
      create_form! form_name, step
    rescue NameError
      nil
    end

    def validate(attributes = {})
      @valid = super
    end

    def save
      validate if @valid.nil?
      return false unless @valid
      super
    end

    # Check if event available for given model
    def can_event?(step)
      model_events.include? step&.to_sym
    end

    # First available event for given model according to model state
    def default_step
      model_events.first
    end

    # Steps for view render
    def steps
      %i[upload setup order]
    end

    def file_url
      model.model_file&.file_url
    end

    def simulation_model
      model.simulation
    end

    def user
      model.user.decorate
    end

    private

    # Events available for a given model according to model state
    def model_events
      [state_events].flatten
    end

    def create_form!(name, step)
      klass = Class.new(self.class).include(name)
      form = klass.new(model)
      form.state = model.state unless model.state.blank? # overrides initial state
      form.state_event = step
      form
    end
  end

  def factory(model)
    factory = Factory.new(model)
    factory.state = model.state unless model.state.blank? # overrides initial state
    factory
  end

  def events
    Factory.state_machine.events.map(&:name)
  end

  module_function :factory, :events
end
