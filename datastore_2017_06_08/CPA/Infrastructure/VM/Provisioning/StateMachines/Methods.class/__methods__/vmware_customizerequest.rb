

###################################
#
# EVM Automate Method: Select_Cluster
#
# Notes:
# EVM Inputs: miq_provision
# Outputs: miq_provision
# Reqs cluster tags
#
#
###################################
begin
  # Method for logging
  def log(level, message)
    @method = ''
    $evm.log(level, "#{@method} - #{message}")
  end
  @method = 'Select Cluster'
  $evm.log("info", "===== EVM Automate Method: <#{@method}> Started")

  prov = $evm.root["miq_provision"]
  template  = prov.vm_template

  zone = prov.options[:zone]
  data_center = prov.options[:data_center]
  envname = prov.options[:envname]
  os_name = prov.source.platform

  # Retrieve all properly tagged clusters
  eligibleCluster =[]
  clustercandidates = $evm.vmdb(:ems_cluster).all
  $evm.log("info","Clusters: #{clustercandidates} #{os_name}")

  clustercandidates.each do |cl|
    clsdc = cl.v_parent_datacenter
    log(:info,"Cluster #{clsdc}")
     next if clsdc == "IMC4"

          if (zone == "Blue") && (cl.tagged_with?(:clsrole, 'restrict'))
            eligibleCluster << cl
            log(:info,"CPACF: Adding Eligible Blue Clusters #{cl.name} to eligible list count: #{eligibleCluster.length}")
          elsif (zone == "Orange") && (cl.tagged_with?(:clsrole, 'dmz'))
              eligibleCluster << cl
              log(:info,"CPACF: Adding Eligible Orange Clusters #{cl.name} to eligible list count: #{eligibleCluster.length}")
          elsif (os_name == "linux") && (cl.tagged_with?(:clsrole, 'linux'))
              eligibleCluster << cl
              log(:info,"CPACF: Adding Eligible Linux Clusters #{cl.name} to eligible list count: #{eligibleCluster.length}")
          elsif (os_name == "windows") && (cl.tagged_with?(:clsrole, 'win'))
              eligibleCluster << cl
              log(:info,"CPACF: Adding Eligible Windows Clusters #{cl.name} to eligible list count: #{eligibleCluster.length}")
          else
            log(:info,"CPACF: Eligible Clusters NOT found")
          end # end if
      log(:info,"Processing Eligible Clusters")
    end # end do

    # Process cluster list in first desired order
    eligibleCluster.each do |cl|
      prov.set_cluster(cl)
      #prov.set_option(:best_cluster, cl)
      log(:info, "Cluster: #{cl.name}")
      template_name = template.name
      log(:info, "Checking for Template: #{template_name}")
      dc_name = cl.v_parent_datacenter
      log(:info, "Datacenter Name: #{dc_name}")
      ems = cl.ext_management_system
      #dc_folder = ems.ems_folders.detect {|f| f.name == dc_name && f.is_datacenter == true}
      #log(:info, "DC Folder: #{dc_folder.inspect}")
      #vm_template = ems.vms.detect {|v| v.name == template_name && v.template == true && v.parent_blue_folder_1_name == dc_name}
=begin      templist = $evm.vmdb("miq_template").find_all_by_name(template_name)
      vm_template = templist.detect {|t|t.ext_management_system.name == ems.name && t.parent_blue_folder_1_name == dc_name && (!t.archived|!t.orphand)}
      log(:info, "New VM template: #{vm_template.inspect}")
      prov.set_option(:src_vm_id, [vm_template.id, vm_template.name])
      log(:info, "Template: #{vm_template.name} now reset to new datacenter #{dc_name}")
=end
    end #end do

  #
  # Exit method
  #
  $evm.log("info", "=== EVM Automate Method: <#{@method}, Selected Cluster, name: <#{prov.get_option(:best_cluster)}> Ended")
  exit MIQ_OK

    #
    # Set Ruby rescue behavior
    #
rescue => err
  $evm.log("error", "<#{@method}>: [#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end
