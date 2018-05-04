$evm.instantiate '/Integration/ITSM/BmcRemedy/StateMachines/ProjectQuery'
exit MIQ_ABORT unless $evm.root['ae_result'] == 'ok'
exit MIQ_OK
