#
# Description: <Method description here>
#
prov = $evm.root['miq_provision']
vm = prov.vm
size_of_disks = prov.options[:size_of_disks]
$evm.log('info', "CPACF: SIZES: #{size_of_disks}; VM NAME: #{vm.name}; STORAGE NAME: #{vm.storage.name}")
if !size_of_disks.nil? && !size_of_disks.empty?
  size_of_disks.split(/, ?/).each do |size|
    real_size = size.to_i * 1024
    $evm.log('info', "CPACF: Adding #{real_size} GB drive to #{vm.name} at #{vm.storage.name}")
    sleep 15
    rc = vm.add_disk("[#{vm.storage.name}]", real_size)
    $evm.log('info', "CPACF: RC: #{rc}")
  end
else
  $evm.log('info', "CPACF: No extra disks requested")
end
