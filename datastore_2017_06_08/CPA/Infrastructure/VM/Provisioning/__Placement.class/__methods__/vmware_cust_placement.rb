

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

  # Retrieve all properly tagged clusters
  eligibleCluster =[]
  clustercandidates = $evm.vmdb(:ems_cluster).all.name
  $evm.log("info","Clusters: #{clustercandidates}")

  clustercandidates.each do |cl|
    log(:info,"Cluster #{cl.v_parent_datacenter.inspect}")

          if cl.tagged_with?(:ClusterRole, 'restrict')
            eligibleCluster << cl
            log(:info,"CPACF: Adding Eligible Blue Clusters #{cl.name} to eligible list count: #{eligibleCluster.length}")
            next
          elsif cl.tagged_with?(:ClusterRole, 'dmz')
              eligibleCluster << cl
              log(:info,"CPACF: Adding Eligible Orange Clusters #{cl.name} to eligible list count: #{eligibleCluster.length}")
              next
          elsif cl.tagged_with?(:ClusterRole, 'linux')
              eligibleCluster << cl
              log(:info,"CPACF: Adding Eligible Linux Clusters #{cl.name} to eligible list count: #{eligibleCluster.length}")
              next
          elsif cl.tagged_with?(:ClusterRole, 'win')
              eligibleCluster << cl
              log(:info,"CPACF: Adding Eligible Windows Clusters #{cl.name} to eligible list count: #{eligibleCluster.length}")
              next
          else
            log(:info,"CPACF: Eligible Clusters NOT found")
          end # end if
      log(:info,"Processing Eligible Clusters")
    end # end do

    # Process cluster list in first desired order
    eligibleCluster.each do |cl|
      prov.set_option(:best_cluster, cl)
      log(:info, "Cluster: #{cl.name}")
      template_name = template.name
      log(:info, "Checking for Template: #{template_name}")
      dc_name = cl.v_parent_datacenter
      log(:info, "Datacenter Name: #{dc_name}")
      ems = cl.ext_management_system
      dc_folder = ems.ems_folders.detect {|f| f.name == dc_name && f.is_datacenter == true}
      log(:info, "DC Folder: #{dc_folder.inspect}")
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
