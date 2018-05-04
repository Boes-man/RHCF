#
# Creates an AWS EC2 volume and attaches to EC2 instance
# RHEl and Windows
# Class requires proxy details.
# Comma separated list of disk sizes.
# TODO: disk_device assumes no disks have previously been added to
#       instance outside CF. Move this method/task to configuration
#       management, eg ansible.
# 

def log(level, message)
  method = 'amazon_add_disk'
  $evm.log level, "#{method} - #{message}"
end

def err_to_s(err)
  "[#{err}]\n#{err.backtrace.join '\n'}"
end

def get_aws_client_object(http_proxy, ext_mgt_system, type="EC2")
  require 'aws-sdk'
  log(:info, "PROXY2: #{http_proxy}")
  Aws.config.update({
                        region: ext_mgt_system.provider_region,
                        http_proxy: http_proxy,
                        credentials: Aws::Credentials.new(ext_mgt_system.authentication_userid, ext_mgt_system.authentication_password)
                    })
  return Object::const_get("Aws").const_get("#{type}").const_get("Client").new()
end

def get_aws_instance_object(ext_mgt_system, type="EC2")
  require 'aws-sdk'
  Aws.config.update({
                        region: ext_mgt_system.provider_region,
                        credentials: Aws::Credentials.new(ext_mgt_system.authentication_userid, ext_mgt_system.authentication_password)
                    })
  return Object::const_get("Aws").const_get("#{type}").const_get("Instance").new()
end

# Get the AWS Management System from the various options available
def get_mgt_system()
  aws_mgt = nil
  aws_mgt = $evm.vmdb(:ems_amazon).first
  log(:info, "Got First Available AWS Mgt System from VMDB")
  return aws_mgt
end

def add_disk_amazon(server,disklist,ec2,resource,availabilityzone,platform,letter)
  require 'aws-sdk'
  if platform.include? "Red Hat"
    device_map = "/dev/sd"
  else
    device_map = "xvd"
  end
  disklist.split(/, ?/).each do |size|
    real_size = size.to_i
    volume = ec2.create_volume( {
                                    availability_zone: availabilityzone, # required
                                    size: real_size,
                                    volume_type: "gp2", # accepts standard, io1, gp2, sc1, st1
                                })
    log(:info, "Amazon Volume: #{volume.to_h} being created")
    vol_ids = []
    vol_ids.push(volume['volume_id'])

    begin
      ec2.wait_until(:volume_available, volume_ids:vol_ids)
      log(:info, "Amazon Volume(s): #{vol_ids} ready")
    rescue Aws::Waiters::Errors::WaiterFailed => error
      log(:info, "Failed waiting for Amazon Volume: #{volume.volume_id} : #{error.message}")
    end

    letter = letter.next
    @disk_device = "#{device_map}#{letter}"
    disk = ec2.attach_volume({
                                 device: @disk_device,
                                 instance_id: resource,
                                 volume_id: volume['volume_id'],
                             })
    log(:info, "Amazon Disk: #{disk.to_h} being attached to instance: #{resource}")
    ec2.wait_until(:volume_in_use, volume_ids:vol_ids)
    log(:info, "Amazon Volume(s): #{vol_ids} attached to instance: #{resource}")
    instance = Aws::EC2::Instance.new(id: resource, client: ec2)
    log(:info, "Got EC2 Object: #{instance.inspect}")
    ec2.modify_instance_attribute(block_device_mappings: [
        {
            device_name: @disk_device,
            ebs: {
                delete_on_termination: true,
                volume_id: disk['volume_id'],
            },
        },
    ],
                                  instance_id: resource,)
  end
  server.custom_set :ec2_last_disk, @disk_device
end


begin

  require 'aws-sdk'

  prov = $evm.root["miq_provision"]
  proxy = $evm.object['proxy']
  proxy_user = $evm.object['proxy_user']
  proxy_password = $evm.object.decrypt('proxy_password')
  http_proxy = "http://#{proxy_user}:#{proxy_password}@#{proxy}"
  log(:info, "PROXY: #{http_proxy}")

  # get the AWS Management System Object
  aws_mgt = get_mgt_system()
  log(:info, "AWS Mgt System is #{aws_mgt.inspect}")

  ec2 = get_aws_client_object(http_proxy,aws_mgt)
  log(:info, "Got EC2 Object: #{ec2.inspect}")

  case $evm.root['vmdb_object_type']
    when 'miq_provision' # called from a VM provision workflow
      instance_ems_ref = prov.vm.ems_ref
      availabilityzone = prov.options[:availability_zone]
      disks_list =  prov.options[:size_of_disks]
      exit MIQ_OK if disks_list.nil?
      platform = prov.options[:name]
      server = prov.vm
      letter = "e"
      log(:info, "AWS reconfig: #{server} #{instance_ems_ref} #{availabilityzone} #{disks_list} #{platform} #{letter}")
      if !disks_list.nil? && !disks_list.empty?
        log(:info, "Adding disks to amazon instance: #{instance_ems_ref}")
        add_disk_amazon(server, disks_list,ec2,instance_ems_ref,availabilityzone,platform,letter)
      else
        log(:info, "No disks to add for provision request: #{prov.miq_provision_request.id}")
        exit MIQ_OK
      end
    when 'vm'
      vm = $evm.root['vm'] # called from a button
      ec2_last_device = vm.custom_get :ec2_last_disk
      if !ec2_last_device.nil?
        letter = ec2_last_device.last
      else
        letter = "e"
      end
      instance_ems_ref = vm.ems_ref
      availabilityzone = vm.availability_zone.name
      disks_list = $evm.root['dialog_size_of_disks']
      platform = vm.platform == 'linux' ? 'Red Hat' : 'Windows'
      server = vm
      power_state = vm.attributes['power_state']
      log(:info, "AWS reconfig: #{server} #{instance_ems_ref} #{availabilityzone} #{disks_list} #{platform} #{power_state} #{letter}")
      #$evm.log(:info, "Current VM power state = #{@vm.power_state}")
      if power_state == "off"
        $evm.root['ae_result'] = 'ok'
        add_disk_amazon(server,disks_list,ec2,instance_ems_ref,availabilityzone,platform,letter)
      else
        vm.stop
        vm.refresh
        $evm.root['ae_result'] = 'retry'
        $evm.root['ae_retry_interval'] = '30.seconds'
      end
  end

rescue => err
  log :error, err_to_s(err)
  exit MIQ_ABORT
end

