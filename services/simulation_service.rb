# frozen_string_literal: true

# Simulation control center
class SimulationService
  include SimulationStates
  attr_reader :model, :errors

  def initialize(simulation)
    super()
    @model = simulation
    @state = model.state if model.state
    @errors = []
  end

  # Events transitions
  state_machine do
    before_transition on: %i[start restart], do: :before_start
    before_transition on: :error, do: :before_error
    after_transition on: %i[stop finish error], do: :after_stop
    after_transition on: any, do: :broadcast
  end

  def save
    model.state = state
    model.save!
  end

  def metadata
    rpc_service.rpc_metadata
  end

  def error(error:)
    @errors << error
    super
  end

  def report
    bucket_service.report_url
  end

  private

  def broadcast
    data = { model: model }
    BroadcastService.broadcast("simulation_progress_#{model.project.user_id}", data)
  end

  def before_start
    InstallInstanceJob.perform_later machine
    UserMailer.simulation_started(model.project_id).deliver_later
  end

  def before_error(transition)
    model.failed_state = transition.from
    model.error = @errors.join(',')
    BroadcastService.broadcast("simulation_progress_#{model.project.user_id}", body: "Error: #{model.error}")
  end

  def after_stop
    RemoveInstanceJob.perform_later machine
    if model.finished?
      model.project.finished!
      UserMailer.simulation_finished(model.project_id).deliver_later
    end
  end

  # @TODO CHOOSE CONFIG BY Simulation.accuracy
  def machine
    model.machine ||= Machine.create(
      config: MachineConfig.first
    )
  end

  def rpc_service
    @rpc_service ||= RpcService.new model
  end

  def bucket_service
    @bucket_service ||= BucketService.new model
  end
end
