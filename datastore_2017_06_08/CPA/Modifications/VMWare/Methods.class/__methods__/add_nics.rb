#
# Description: <Method description here>
#
begin
 # $evm.instantiate('/ObjectWalker/ObjectWalker/objectwalker')
    @task = $evm.root['miq_provision_request'] || $evm.root['miq_provision'] || $evm.root['miq_provision_request_template']
    if  @task.miq_provision_request.source_type == 'ServiceTemplate' then
      vm = @task.vm
      dmzzone = @task.options[:dmzzone]
      datazone = @task.options[:datazone]
      vmnetsm = @task.get_option(:subnet_mask)
      baas = @task.options[:baas]
      vmip = @task.options[:ip_addr]
      device_type = "VirtualVmxnet3"
      baasip = '10.213.148.226'

      if datazone == "Yes" then
        vmnet = 'Non-Prod-TN|Non-Prod-AP|Blue-1214-IMC3-EPG'
      elsif dmzzone == "Yes" then
        vmnet = 'Non-Prod-TN|Non-Prod-AP|Orange-1446-IMC3-EPG'#'Non-Prod-TN|Non-Prod-AP|Orange-1318-IMC3-EPG'
      else
        vmnet = 'Non-Prod-TN|Non-Prod-AP|Green-2314-IMC3-EPG'
      end

     $evm.log('info', "CPACF: Network Placement #{dmzzone} #{datazone} #{baas} #{vmip} #{vmnet} #{vmnetsm}")

      idx = 0
      @task.set_network_adapter(idx,{:network => vmnet, :devicetype => device_type, :is_dvs => true})
      @task.set_nic_settings(0, {:ip_addr => vmip, :subnet_mask => vmnetsm, :addr_mode => ['static', 'Static']})
      $evm.log('info', "CPACF: Primary adapter added")

      if baas == 'Yes'
        idx = 1
        @task.set_network_adapter(idx,{:network => vmnet, :devicetype => device_type, :is_dvs => true})
        @task.set_nic_settings(1, {:ip_addr => baasip, :subnet_mask => vmnetsm, :addr_mode => ['static', 'Static']})
        $evm.log('info', "CPACF: BaaS adapter added")
      end
    end
end
