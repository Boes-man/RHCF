#
# Description: This method Performs the following functions:
# 1. YAML load the Service Dialog Options from @task.get_option(:parsed_dialog_options))
# 2. Set the name of the service
# 3. Set tags on the service
# 5. Override miq_provision task with any options and tags
# Important - The dialog_parser automate method has to run prior to this in order to populate the dialog information.
#
def log_and_update_message(level, msg, update_message = false)
  $evm.log(level, msg.to_s)
  @task.message = msg if @task && (update_message || level == 'error')
end

# Loop through all tags from the dialog and create the categories and tags automatically
def create_tags(category, single_value, tag)
  # Convert to lower case and replace all non-word characters with underscores
  category_name = category.to_s.downcase.gsub(/\W/, '_')
  tag_name = tag.to_s.downcase.gsub(/\W/, '_')
  # if the category exists else create it
  unless $evm.execute('category_exists?', category_name)
    log_and_update_message(:info, "Creating Category: {#{category_name} => #{category}}")
    $evm.execute('category_create', :name         => category_name,
                                    :single_value => single_value,
                                    :description  => category.to_s)
  end
  # if the tag exists else create it
  return if $evm.execute('tag_exists?', category_name, tag_name)
  log_and_update_message(:info, "Creating tag: {#{tag_name} => #{tag}}")
  $evm.execute('tag_create', category_name, :name => tag_name, :description => tag.to_s)
end

def create_category_and_tags_if_necessary(dialog_tags_hash)
  dialog_tags_hash.each do |category, tag|
    Array.wrap(tag).each do |tag_entry|
      create_tags(category, true, tag_entry)
    end
  end
end

def override_service_name(dialog_options_hash)
  log_and_update_message(:info, "Processing override_service_name...", true)
  new_service_name = dialog_options_hash.fetch(:service_name, nil)
  new_service_name = "#{@service.name}-#{Time.now.strftime('%Y%m%d-%H%M%S')}" if new_service_name.blank?

  log_and_update_message(:info, "Service name: #{new_service_name}")
  @service.name = new_service_name
  log_and_update_message(:info, "Processing override_service_name...Complete", true)
end

def override_service_description(dialog_options_hash)
  log_and_update_message(:info, "Processing override_service_description...", true)
  new_service_description = dialog_options_hash.fetch(:service_description, nil)
  return if new_service_description.blank?

  log_and_update_message(:info, "Service description #{new_service_description}")
  @service.description = new_service_description
  log_and_update_message(:info, "Processing override_service_description...Complete", true)
end

def tag_service(dialog_tags_hash)
  return if dialog_tags_hash.nil?

  log_and_update_message(:info, "Processing tag service...", true)

  dialog_tags_hash.each do |key, value|
    log_and_update_message(:info, "Processing Tag Key: #{key.inspect}  value: #{value.inspect}")
    next if value.blank?
    get_service_tags(key.downcase, value)
  end
  log_and_update_message(:info, "Processing tag_service...Complete", true)
end

def get_service_tags(tag_category, tag_value)
  Array.wrap(tag_value).each do |tag_entry|
    assign_service_tag(tag_category, tag_entry)
  end
end

def assign_service_tag(tag_category, tag_value)
  $evm.log(:info, "Adding tag category: #{tag_category} tag: #{tag_value} to Service: #{@service.name}")
  @service.tag_assign("#{tag_category}/#{tag_value}")
end


# This function takes care of naming a set of VMs with all unique names.
# This function also ensures that there is no other service trying to name VMs
# with the same prefix at the same time to avoid VM name duplication.
#
# EXPECTED
#   EVM ROOT
#     service_template_provision_task - service task to set the VM names for
#       required options:
#         dialog
#           dialog_vm_prefix - VM name prefix to use when naming VMs.
#
# @see https://pemcg.gitbooks.io/mastering-automation-in-cloudforms-4-2-and-manage/content/the_service_provisioning_state_machine/chapter.html#_vm_naming_for_services
# @see https://pemcg.gitbooks.io/mastering-automation-in-cloudforms-4-2-and-manage/content/service_objects/chapter.html
#
def get_vm_prefix
  @DEBUG = false

  @retry_interval                = 10
  @default_suffix_counter_lenght = 3

  # Log an error and exit.
  #
  # @param msg Message to error with
  def error(msg)
    $evm.log(:error, msg)
    $evm.root['ae_result'] = 'error'
    $evm.root['ae_reason'] = msg.to_s
    exit MIQ_STOP
  end


  # Calls a user provided block for each grand child of the given parent.
  #
  # @param parent             Parent of grand children to call the given block for
  # @block |grand_child_task| Call the given block for each grand child of the given parent
  def for_each_grand_child_task(parent)
    parent.miq_request_tasks.each do |child_task|
      child_task.miq_request_tasks.each do |grand_child_task|
        # call block passing grand child MiqProvision
        yield grand_child_task
      end
    end
  end

  # Calls a user provided block for each active or pending requests.
  # Optionally does not call for the given current request.
  #
  # @param current_request             Optional. Current request to not call the block for.
  # @param request_type                The type of active or pending requests to iterate over
  # @block |active_or_pending_request| Call this block for each active or pending request.
  def for_each_active_or_pending_request(current_request = nil, request_type = 'ServiceTemplateProvisionRequest')
    $evm.vmdb(:miq_request).all.each do |request|
      if ( (request.request_state == 'active' || request.request_state == 'pending') &&
           (request_type.nil? || request.type == request_type) &&
           (current_request.nil? || request.id != current_request.id) )

        # call block passing active/pending request
        yield request
      end
    end
  end

  # Given a ServiceTemplateProvisionRequest sets a lock option on that request signifying that the
  # given request is doing VM naming with the given VM prefix.

  def with_service_template_provision_request_naming_lock(current_request, vm_prefix)
    aquired_lock = false
    begin
      # set that the given request is trying to get the vm_naming lock
      $evm.log(:info, "Set lock attempt: { request_id => '#{current_request.id}', :vm_naming_lock_attempt => '#{vm_prefix}' }") if @DEBUG
      current_request.set_option(:vm_naming_lock_attempt, vm_prefix)

      # determine if any active ServiceTemplateProvisionRequests are trying to get a lock or have the lock for the given vm prefix
      $evm.log(:info, "Other Active ServiceTemplateProvisionRequests: { current_request_id => #{current_request.id} }") if @DEBUG
      existing_lock = false
      for_each_active_or_pending_request(current_request) do |request|
        request_vm_naming_lock_attempt = request.get_option(:vm_naming_lock_attempt)
        request_vm_naming_lock         = request.get_option(:vm_naming_lock)
        $evm.log(:info, "Found active ServiceTemplateProvisionRequest: { :id => #{request.id}, :vm_naming_lock_attempt => '#{request_vm_naming_lock_attempt}', :vm_naming_lock => '#{request_vm_naming_lock}' }") if @DEBUG

        # if the active ServiceTemplateProvisionRequest is trying to get lock or has lock, then this task can't have it
        if ( (!request_vm_naming_lock.nil? && request_vm_naming_lock == vm_prefix) ||
             (!request_vm_naming_lock_attempt.nil? && request_vm_naming_lock_attempt == vm_prefix) )

          # found existing request that already has lock
          $evm.log(:info, "Found active ServiceTemplateProvisionRequest with lock or attempting to get lock: { request_id => '#{request.id}', :vm_naming_lock_attempt => '#{request_vm_naming_lock_attempt}', :vm_naming_lock => '#{request_vm_naming_lock}' }") if @DEBUG
          existing_lock = true
          break
        end
      end

      # if another active ServiceTemplateProvisionRequest already has the lock or is trying to get the lock then can't get lock
      # else claim the lock
      if existing_lock
        $evm.log(:info, "ServiceTemplateProvisionRequest Failed to get lock: { request_id => '#{current_request.id}', :vm_naming_lock => '#{vm_prefix}' }") if @DEBUG
        aquired_lock = false
      else
        begin
          $evm.log(:info, "ServiceTemplateProvisionRequest Claim lock: { request_id => '#{current_request.id}', :vm_naming_lock => '#{vm_prefix}' }") if @DEBUG
          current_request.set_option(:vm_naming_lock, vm_prefix)
          aquired_lock = true

          # yield to the user block
          yield
        ensure
          $evm.log(:info, "ServiceTemplateProvisionRequest Release lock: { request_id => '#{current_request.id}', :vm_naming_lock => '#{vm_prefix}' }") if @DEBUG
          current_request.set_option(:vm_naming_lock, nil)
        end
      end
    ensure
      $evm.log(:info, "ServiceTemplateProvisionRequest Release lock attempt: { request_id => '#{current_request.id}', :vm_naming_lock_attempt => '#{vm_prefix}' }") if @DEBUG
      current_request.set_option(:vm_naming_lock_attempt, nil)
    end

    return aquired_lock
  end

  # Determines a unique VM name using the given VM name prefix, and optional given domain name,
  # avoiding any names already in the given list.

  def get_vm_name(vm_prefix, used_vm_names, suffix_counter_length = @default_suffix_counter_lenght)
    counter_max = ("9" * suffix_counter_length).to_i
    vm_name = nil
    for i in (1..(counter_max+1))
      if i > counter_max
        error("Counter exceeded max (#{counter_max}) for prefix (#{vm_prefix})")
      else
        vm_name = "#{vm_prefix}#{i.to_s.rjust(suffix_counter_length, "0")}"
        no_existing_vm_in_vmdb = $evm.vmdb('vm_or_template').find_by_name(vm_name).blank?
        not_in_used_vm_names   = !used_vm_names.include?(vm_name)
        $evm.log(:info, "get_vm_name: { vm_name => '#{vm_name}', no_existing_vm_in_vmdb => #{no_existing_vm_in_vmdb}, not_in_used_vm_names => #{not_in_used_vm_names} }") if @DEBUG

        # stop searching if no VM with given name already exists
        break if no_existing_vm_in_vmdb && not_in_used_vm_names
      end
    end

    $evm.log(:info, "get_vm_name: '#{vm_name}'") if @DEBUG
    return vm_name
  end

  begin
    $evm.log(:info, "START - set_vm_names") if @DEBUG

    # get the current ServiceTemplateProvisionTask
    task = $evm.root['service_template_provision_task']
    error("$evm.root['service_template_provision_task'] not found") if task.nil?
    $evm.log(:info, "Current ServiceTemplateProvisionTask: { :id => '#{task.id}', :miq_request_id => '#{task.miq_request.id}' }") if @DEBUG

    # build the VM name prefix
    data_center = task.get_option(:dialog)['dialog_data_center']
    envname = task.get_option(:dialog)['dialog_envname']
    dmzzone = task.get_option(:dialog)['dialog_dmzzone']
    datazone = task.get_option(:dialog)['dialog_datazone']
    os_name = task.destination.name
    srvprefix = $evm.object['srv_prefix']

    app = task.get_option(:dialog)['dialog_job_template_name']
    a = app.split(".")
    sa = a[2]

    @h = Hash.new
    if datazone == "Yes" then
      @h[:vmnet] = 'Non-Prod-TN|Non-Prod-AP|Blue-1214-IMC3-EPG'
      @h[:cluster_name] = 'IMC3_NonProd_Blue_Clus'
      @h[:zone] = 'Blue'
    elsif dmzzone == "Yes" then
      @h[:vmnet] =  'Non-Prod-TN|Non-Prod-AP|Orange-1446-IMC3-EPG'
      @h[:cluster_name] = 'IMC3_NonProd_DMZ_Clus'
      @h[:zone] = 'Orange'
    elsif os_name.include? "Windows" then
      @h[:vmnet] = 'Non-Prod-TN|Non-Prod-AP|Green-2314-IMC3-EPG'
      @h[:cluster_name] = 'IMC3_NonProd_Win_Clus'
      @h[:zone] = 'Green'
    else
      @h[:vmnet] = 'Non-Prod-TN|Non-Prod-AP|Green-2314-IMC3-EPG'
      @h[:cluster_name] = 'IMC3_NonProd_Linux_Clus'
      @h[:zone] = 'Green'
    end

    env_name = case envname
    when "Non-Prod" then "5"
    else "0"
    end

    dc = case data_center
    when "IMC3" then "X3"
    when "IMC4" then "X4"
    else "XX"
    end

    if os_name.include? "Windows"
      os = "W"
    elsif os_name.include? "Redhat"
      os = "L"
    end

    vm_prefix = "#{srvprefix}#{dc}#{os}#{sa}#{env_name}".upcase

    $evm.log(:info, "vm_prefix => '#{vm_prefix}'") if @DEBUG
    #error("dialog_vm_prefix not found in ServiceTemplateProvisionTask dialog options: { :id => '#{task.id}', :miq_request_id => '#{task.miq_request.id}' }") if vm_prefix.blank

    current_request = task.miq_request
    aquired_lock = with_service_template_provision_request_naming_lock(current_request, vm_prefix) do
    used_vm_names = []

    # get the VM names on all current active requests so as not to conflict with those
    $evm.log(:info, "Other Active ServiceTemplateProvisionRequests: { current_task_id => #{task.id}, current_request_id => #{current_request.id} }") if @DEBUG
    for_each_active_or_pending_request(current_request) do |request|
      $evm.log(:info, "\tActive ServiceTemplateProvisionRequest VM Names: { other_active_request_id => #{request.id} }") if @DEBUG

      for_each_grand_child_task(request) do |grand_child_task|
        existing_vm_target_name = grand_child_task.get_option(:vm_target_name)
        $evm.log(:info, "\t\tOther Active ServiceTemplateProvisionRequest VM name: { grand_child_task => #{grand_child_task.id}, existing_vm_target_name => '#{existing_vm_target_name}' }") if @DEBUG

        # add the concurrent service request VM name to the list of used vm names so there are no conflicts
        used_vm_names.push(existing_vm_target_name)
      end
    end

    # for each VM request generate a unique name and keep track of the names used in this batch
    for_each_grand_child_task(task) do |grand_child_task|
      # get the unique vm name
      vm_name = get_vm_name(vm_prefix, used_vm_names)
      used_vm_names.push(vm_name)

      # set the target vm name
      grand_child_task.set_option(:vm_target_name, vm_name)
      grand_child_task.set_option(:vm_target_hostname, vm_name)
      grand_child_task.set_option(:vm_name, vm_name)

      $evm.log(:info, "Set grand_child_task options: { current_request_id => #{current_request.id}, grand_child_task_id => '#{grand_child_task.id}', :vm_target_name => '#{grand_child_task.get_option(:vm_target_name)}', :vm_target_hostname => '#{grand_child_task.get_option(:vm_target_hostname)}' }")
    end
  end

  # if did not acquire lock then retry after interval
  # else done
  unless aquired_lock
    $evm.log(:info, "Did not acquire VM naming lock '#{vm_prefix}', retry after interval '#{@retry_interval}'")
    $evm.root['ae_result'] = 'retry'
    $evm.root['ae_retry_interval'] = "#{@retry_interval}.seconds"
  else
    $evm.root['ae_result'] = 'ok'
  end

  $evm.log(:info, "END - set_vm_names") if @DEBUG
  rescue => err
  error("[#{err}]\n#{err.backtrace.join("\n")}")
  end
  end

def set_vm_name(dialog_options_hash, prov)
  log_and_update_message(:info, "Processing set_vm_name", true)
  new_vm_name = dialog_options_hash.fetch(:vm_name, nil) || dialog_options_hash.fetch(:vm_target_name, nil)
  if new_vm_name.blank?
    set_all_vm_name_attrs(prov, prov.get_option(:vm_target_name))
    log_and_update_message(:info, "Using default vm name: #{prov.get_option(:vm_target_name)}", true)
  else
    set_all_vm_name_attrs(prov, new_vm_name)
    log_and_update_message(:info, "Setting vm name to: #{prov.get_option(:vm_target_name)}", true)
  end
  log_and_update_message(:info, "Processing set_vm_name...Complete", true)
end

def set_all_vm_name_attrs(prov, new_vm_name)
  prov.set_option(:vm_target_name, new_vm_name)
  prov.set_option(:vm_target_hostname, new_vm_name)
  prov.set_option(:vm_name, new_vm_name)
  prov.set_option(:linux_host_name, new_vm_name)
end

def service_item_dialog_values(dialogs_options_hash)
  merged_options_hash = Hash.new { |h, k| h[k] = {} }
  provision_index = determine_provision_index

  if dialogs_options_hash[0].nil?
    merged_options_hash = dialogs_options_hash[provision_index] || {}
  else
    merged_options_hash = dialogs_options_hash[0].merge(dialogs_options_hash[provision_index] || {})
  end
  merged_options_hash
end

def service_item_tag_values(dialogs_tags_hash)
  merged_tags_hash         = Hash.new { |h, k| h[k] = {} }
  provision_index = determine_provision_index

  # merge dialog_tag_0 stuff with current build
  if dialogs_tags_hash[0].nil?
    merged_tags_hash = dialogs_tags_hash[provision_index] || {}
  else
    merged_tags_hash = dialogs_tags_hash[0].merge(dialogs_tags_hash[provision_index] || {})
  end
  merged_tags_hash
end

def determine_provision_index
  service_resource = @task.service_resource
  if service_resource
    # Increment the provision_index number since the child resource starts with a zero
    provision_index = service_resource.provision_index ? service_resource.provision_index + 1 : 0
    log_and_update_message(:info, "Bundle --> Service name: #{@service.name}> provision_index: #{provision_index}")
  else
    provision_index = 1
    log_and_update_message(:info, "Item --> Service name: #{@service.name}> provision_index: #{provision_index}")
  end
  provision_index
end

def add_provision_tag(key, value, prov)
  log_and_update_message(:info, "Adding Tag: {#{key.inspect} => #{value.inspect}} to Provisioning id: #{prov.id}")
  prov.add_tag(key.to_s.downcase.gsub(/\W/, '_'), value.to_s.downcase.gsub(/\W/, '_'))
end

def get_provision_tags(key, value, prov)
  Array.wrap(value).each do |tag_entry|
    add_provision_tag(key, tag_entry.downcase, prov)
  end
end

def tag_provision_task(dialog_tags_hash, prov)
  dialog_tags_hash.each do |key, value|
    get_provision_tags(key, value, prov)
  end
end

def set_option_on_provision_task(dialog_options_hash, prov)
  dialog_options_hash.each do |key, value|
    log_and_update_message(:info, "Adding Option: {#{key} => #{value}} to Provisioning id: #{prov.id}")
    prov.set_option(key, value)
  end
  @h.each do |key, value|
    log_and_update_message(:info, "Adding Option: {#{key} => #{value}} to Provisioning id: #{prov.id}")
    prov.set_option(key, value)
  end
end

def set_option_on_destination(dialog_options_hash, destination)
  dialog_options_hash.each do |key, value|
    log_and_update_message(:info, "Adding Option: {#{key} => #{value}} to Destination id: #{destination.id}")
    destination.set_dialog_option(destination_key_name(key), value)
  end
end

def destination_key_name(key)
  key = key.to_s
  return key if key.include?("::") || key.starts_with?("dialog_")
  "dialog_#{key}"
end

def pass_dialog_values_to_provision_task(provision_task, dialog_options_hash, dialog_tags_hash)
  provision_task.miq_request_tasks.each do |prov|
    log_and_update_message(:info, "Grandchild Task: #{prov.id} Desc: #{prov.description} type: #{prov.source_type}")
    get_vm_prefix
    set_vm_name(dialog_options_hash, prov)
    tag_provision_task(dialog_tags_hash, prov)
    set_option_on_provision_task(dialog_options_hash, prov)
  end
end

def pass_dialog_values_to_children(dialog_options_hash, dialog_tags_hash)
  return if dialog_options_hash.blank? && dialog_tags_hash.blank?

  set_option_on_destination(dialog_options_hash, @task.destination)

  @task.miq_request_tasks.each do |t|
    child_service = t.destination
    log_and_update_message(:info, "Child Service: #{child_service.name}")
    next if t.miq_request_tasks.nil?

    pass_dialog_values_to_provision_task(t, dialog_options_hash, dialog_tags_hash)
  end
end

def remove_service
  log_and_update_message(:info, "Processing remove_service...", true)
  if @service
    log_and_update_message(:info, "Removing Service: #{@service.name} id: #{@service.id} due to failure")
    @service.remove_from_vmdb
  end
  log_and_update_message(:info, "Processing remove_service...Complete", true)
end

def merge_dialog_information(dialog_options_hash, dialog_tags_hash)
  merged_options_hash = service_item_dialog_values(dialog_options_hash)
  merged_tags_hash = service_item_tag_values(dialog_tags_hash)

  log_and_update_message(:info, "merged_options_hash: #{merged_options_hash.inspect}")
  log_and_update_message(:info, "merged_tags_hash: #{merged_tags_hash.inspect}")
  return merged_options_hash, merged_tags_hash
end

def yaml_data(option)
  @task.get_option(option).nil? ? nil : YAML.load(@task.get_option(option))
end

def parsed_dialog_information
  dialog_options_hash = yaml_data(:parsed_dialog_options)
  dialog_tags_hash = yaml_data(:parsed_dialog_tags)
  if dialog_options_hash.blank? && dialog_tags_hash.blank?
    log_and_update_message(:info, "Instantiating dialog_parser to populate dialog options")
    $evm.instantiate('/Service/Provisioning/StateMachines/Methods/DialogParser')
    dialog_options_hash = yaml_data(:parsed_dialog_options)
    dialog_tags_hash = yaml_data(:parsed_dialog_tags)
  end

  merged_options_hash, merged_tags_hash = merge_dialog_information(dialog_options_hash, dialog_tags_hash)
  return merged_options_hash, merged_tags_hash
end

begin

  @task = $evm.root['service_template_provision_task']

  @service = @task.destination
  log_and_update_message(:info, "Service: #{@service.name} Id: #{@service.id} Tasks: #{@task.miq_request_tasks.count}")

  dialog_options_hash, dialog_tags_hash = parsed_dialog_information

  unless dialog_options_hash.blank?
    override_service_name(dialog_options_hash)
    override_service_description(dialog_options_hash)
  end

  unless dialog_tags_hash.blank?
    create_category_and_tags_if_necessary(dialog_tags_hash)
    tag_service(dialog_tags_hash)
  end

  pass_dialog_values_to_children(dialog_options_hash, dialog_tags_hash)

rescue => err
  log_and_update_message(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  @task.finished(err.to_s) if @task
  remove_service if @service
  exit MIQ_ABORT
end
