# frozen_string_literal: true

module Providers
  # Google provider wrapper class
  # Config: config/initializers/google_provider.rb
  class GoogleProvider < BaseProvider

    REQUIRED_CONFIG = {
      connection: %i[key project],
      storage: %i[key project bucket]
    }.freeze

    def create(auto_delete_disk: true, **options)
      data = create_data options
      disk_data = options[:disk].merge(name: data[:name], zone: data[:zone])
      disk = create_disk(disk_data)
      disk.wait_for(&:ready?)
      data[:disks] = [disk]

      instance = create_instance(data) do |i|
        i.wait_for(&:ready?)
      end

      instance.set_disk_auto_delete true if auto_delete_disk
      instance
    end

    def remove(name)
      instance = instance(name, raise: true)
      instance.destroy
    end

    def create_dir(path)
      path += '/' unless path.end_with? '/'
      bucket.files.new(key: path).save
      file(path)&.key
    end

    def files(prefix = nil)
      storage.files(directory: bucket, prefix: prefix)
    end

    def file(name)
      bucket.files.get(name)
    end

    def delete_file(name)
      bucket.files.destroy(name)
    end

    def upload_url(name)
      "#{base_upload_url}b/#{config.bucket}/o?uploadType=media&name=#{name}"
    end

    def images_list
      result = images.service.list_images(config.project)
      result&.items || []
    end

    def types_list(zone:)
      connection.machine_types.all(zone: zone) || []
    end

    def zones_list
      zones || []
    end

    # @param [Hash] filter
    def instances_list(filter:)
      servers.all(filter: normalize_filter(filter))
    end

    private

    def connection
      @connection ||= Fog::Compute::Google.new(
        google_project: config.project,
        google_json_key_location: config.key
      )
    rescue ArgumentError
      raise InitializeError.new(
        get_required(REQUIRED_CONFIG[:connection]),
        self.class
      )
    end

    def storage
      @storage ||= Fog::Storage::Google.new(
        google_project: config.project,
        google_json_key_location: config.key
      )
    rescue ArgumentError
      raise InitializeError.new(
        get_required(REQUIRED_CONFIG[:storage]),
        self.class
      )
    end

    def bucket
      @bucket ||= storage.directories.get(config.bucket)
    end

    # Fog storage service object
    def storage_service
      storage.storage_json
    end

    def base_upload_url
      storage_service.root_url + storage_service.upload_path
    end

    def find(subject, name, params = {})
      result = connection.send(subject).get(name)
      if params[:raise]
        raise NotFoundError, "#{subject} with name: #{name} not found" unless result
      end
      result
    end

    def get_required(required)
      required - config.to_h.keys
    end

    def create_data(params)
      {
        name: check_name(params[:name]),
        machine_type: params[:type],
        zone: zone(params[:zone], raise: true)&.name,
        network_interfaces: create_network(params[:network]),
        metadata: { items: create_metadata(params[:metadata]) },
        service_accounts: config.service_accounts,
        labels: create_labels(params[:labels])
      }
    end

    def create_labels(labels)
      return unless labels.is_a? Hash
      labels
    end

    def create_metadata(params)
      params.map { |k, v| { key: k, value: v } }
    end

    def create_network(network)
      [
        network: network(network, raise: true)&.self_link,
        access_configs: [{ name: 'External NAT', type: 'ONE_TO_ONE_NAT' }]
      ]
    end

    def create_instance(params)
      validate_required params, keys: %i[name zone machine_type disks network_interfaces]
      machine = servers.create params
      yield machine if block_given?
      machine
    rescue StandardError => e
      params[:disks].each do |disk|
        disk&.destroy
      end
      raise e
    end

    def create_disk(params)
      validate_required params, keys: %i[image size name zone]
      data = {
        name: params[:name],
        source_image: image(params[:image], raise: true)&.self_link,
        size_gb: params[:size],
        zone_name: params[:zone]
      }
      disks.create(data)
    end

    def check_name(name)
      instance = instance(name)
      unless instance.blank?
        raise DuplicateInstanceName, "Instance with name: #{name} already exists"
      end
      name
    end

    def normalize_filter(filter)
      raise InvalidFilter, "Filter must be Hash (name: 'test')" unless filter.is_a? Hash
      result = flat_hash filter
      result.map { |k, v| "#{k} eq #{v}" }.join(' AND ')
    end

    def flat_hash(hash, keys = [], result = {})
      return result.update(keys.join('.') => hash) unless hash.is_a? Hash
      hash.each { |key, value| flat_hash(value, keys + [key], result) }
      result
    end
  end
end
