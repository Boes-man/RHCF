#
# Description: <Method description here>
#
prov = $evm.root['miq_provision']
vm = prov.vm
vm_size = prov.options[:vm_size]
$evm.log(:info, "CPACF: Requested VM size: #{vm_size}")
case vm_size
  when "Small"
    cpu = 1
  	ram = 2048
  when "Medium"
    cpu = 2
  	ram = 2048
  when "Large"
    cpu = 4
  	ram = 4096
  else
    cpu = 1
  	ram = 1024
end
$evm.log(:info, "CPACF: Set amount of memory to #{ram} and set number of CPUs to #{cpu} for #{vm.name}")
vm.set_memory(ram)
vm.set_number_of_cpus(cpu)
