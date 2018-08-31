# frozen_string_literal: true

# Domain specific deploy service
class DeployService
  attr_reader :machine, :provider, :error

  def initialize(machine:, provider: Providers::GoogleProvider)
    @machine = machine
    @provider = provider
  end

  def self.instance_list(provider: Providers::GoogleProvider)
    provider.new.instances_list(filter: { labels: Machine::LABELS })
  end

  def create_instance!
    params = instance_params.merge(
      name: machine.full_name,
      auto_delete_disk: true,
      metadata: simulation_service.metadata.merge(startup_script)
    )
    machine.running! if provider.create params
  rescue StandardError => e
    @error = e.message
    raise e
  end

  def remove_instance!
    machine.stopped! if provider.remove(machine.full_name)
  rescue StandardError => e
    @error = e
    raise e
  end

  def simulation_service
    @simulation_service ||= SimulationService.new machine.simulation
  end

  private

  def config
    machine.config
  end

  def instance_params
    {
      user: ENV['USER'],
      disk: disk_params,
      network: config.network,
      zone: config.zone,
      type: config.type,
      labels: Machine::LABELS
    }
  end

  def disk_params
    {
      image: config.image,
      size: config.disc_size
    }
  end

  def startup_script
    if File.exist? config.startup_path
      # noinspection RubyStringKeysInHashInspection
      return { 'startup-script' => File.read(path) }
    end
    {}
  end
end
