# list_job_templates.rb
#
# Author: Jeff Watts 
# License: GPL v3
#
# Description: Build Dialog of all Ansible Job tempalate guids based on the RBAC filters applied to a users group
#
def get_user
  user_search = $evm.root['dialog_userid'] || $evm.root['dialog_evm_owner_id']
  user = $evm.vmdb('user').find_by_id(user_search) || $evm.vmdb('user').find_by_userid(user_search) ||
    $evm.root['user']
  user
end

def get_current_group_rbac_array(user, rbac_array=[])
  unless user.current_group.filters.blank?
    user.current_group.filters['managed'].flatten.each do |filter|
      next unless /(?<category>\w*)\/(?<tag>\w*)$/i =~ filter
      rbac_array << {category=>tag}
    end
  end
  $evm.log(:info, "rbac filters: #{rbac_array}")
  rbac_array
end

def template_eligible?(rbac_array, template, os_tag)
#  return false if template.archived || template.orphaned
  rbac_array.each do |rbac_hash|
    rbac_hash.each {|category, tag| return false unless template.tagged_with?(category, tag) && template.tagged_with?("os_base", os_tag)}
  end
  $evm.log(:info, "template: #{template.name} is eligible")
  true
end

user = get_user
rbac_array = get_current_group_rbac_array(user)

object_type = $evm.root['vmdb_object_type']
$evm.log(:info, "JSW: OBJECT_TYPE #{object_type}")
if object_type == "service_template"
  serv_temp = $evm.root['service_template']
  serv_temp.tags.each do |dtag|
    if dtag.split('/')[0] == "os_base"
      @os_name = dtag.split('/')[1]
      $evm.log(:info, "CPACF: OS_NAME #{@os_name}")
    end
  end
else
  if object_type == "vm"
    vm = $evm.root['vm']
    @os_name = vm.os_image_name
    $evm.log(:info, "CPACF: OS_NAME-V #{@os_name}")
  end
end

$evm.log(:info, "CPACF: OS_NAME #{@os_name}")

dialog_hash = {}
$evm.vmdb(:configuration_script).all.each do |template|
  if template_eligible?(rbac_array, template, @os_name)
    dialog_hash[template[:name]] = "#{template.name} on #{template.manager.name}"
  end
end

if dialog_hash.blank?
  $evm.log(:info, "CPACF: No Templates found")
  dialog_hash[''] = "< No Templates found >"
else
  dialog_hash[''] = '< Choose a job template >'
end

$evm.object["values"] = dialog_hash
$evm.log(:info, "$evm.object['values']: #{$evm.object['values'].inspect}")
