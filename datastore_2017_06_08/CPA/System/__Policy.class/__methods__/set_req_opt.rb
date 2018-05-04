# Get variables

def log(level, message)
  @method = ''
  $evm.log(level, "#{@method} - #{message}")
end
#prov = $evm.root["miq_provision"]
@task = $evm.root['miq_request'] || $evm.root['service_template_provision_request'] || $evm.root['miq_provision_request_template']
#vm = @task.vm_template

$evm.instantiate('/ObjectWalker/ObjectWalker/objectwalker')

=begin datazone = @task.options[:datazone]
data_center = @task.options[:data_center]
envname = @task.options[:envname]
os_name = @task.source.platform
=end
os_name = @task.source.name
zone = 'Yellow'
eligibleCluster = []

#cluster = $evm.vmdb(:ems_cluster).find_by_name(cluster_name)
clustercandidates = $evm.vmdb(:ems_cluster).all
#$evm.log("info","Clusters: #{clustercandidates} #{os_name}")

clustercandidates.each do |cl|
  clsdc = cl.v_parent_datacenter
  log(:info,"Cluster #{clsdc}")
   next if clsdc == "IMC4"

        if (zone == "Blue") && (cl.tagged_with?(:clsrole, 'restrict'))
          eligibleCluster = cl
          log(:info,"CPACF: Adding Eligible Blue Clusters #{cl.name}")
        elsif (zone == "Orange") && (cl.tagged_with?(:clsrole, 'dmz'))
            eligibleCluster = cl
            log(:info,"CPACF: Adding Eligible Orange Clusters #{cl.name}")
        elsif (os_name.include? "Redhat") && (cl.tagged_with?(:clsrole, 'linux'))
            eligibleCluster = cl
            log(:info,"CPACF: Adding Eligible Linux Clusters #{cl.name}")
        elsif (os_name.include? "Windows") && (cl.tagged_with?(:clsrole, 'win'))
            eligibleCluster = cl
            log(:info,"CPACF: Adding Eligible Windows Clusters #{cl.name}")
        else
          log(:info,"CPACF: Eligible Clusters NOT found")
        end # end if
    log(:info,"Processing Eligible Clusters")
  end

$evm.log("info", "Cluster Variables: #{eligibleCluster} #{os_name}")
@task.source.service_resources.set_cluster(eligibleCluster)
