# frozen_string_literal: true

# Buckets service service
class BucketService
  attr_reader :simulation, provider

  EXPIRE_TIME = 1.day

  def initialize(simulation, provider: Providers::GoogleProvider.new)
    @simulation ||= simulation
    @provider = provider
  end

  # find exact file
  def find(name)
    full_path = path + name
    provider.file(full_path)
  end

  def upload_url
    folder = create_result_folder
    provider.upload_url(folder)
  end

  def results
    provider.files(path)
  end

  def report_url
    result = provider.file("#{path}/#{provider.report_name}")
    result&.url(EXPIRE_TIME.from_now)
  end

  def delete_report
    provider.delete_file(path)
  end

  def self.find_report_for(simulation)
    serv = new simulation
    serv.report_url
  end

  private

  def path
    "#{provider.result_path}/#{simulation.user_id}/#{simulation.project_id}"
  end

  def create_result_folder
    provider.create_dir path
  end

end
