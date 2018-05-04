$evm.instantiate '/Integration/LDAP/ActiveDirectory/Methods/CheckADGroup'
exit MIQ_ABORT unless $evm.root['ae_result'] == 'ok'
exit MIQ_OK

# TODO add logic and refator AD method to perform query only and do comparison here
