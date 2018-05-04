def log(level, message)
  method = 'itsm_bmc_remedy_change_complete'
  $evm.log level, "#{method} - #{message}"
end

def err_to_s(err)
  "[#{err}]\n#{err.backtrace.join '\n'}"
end

def response_to_s(response)
  "Rresponse #{{code: response.code, headers: response.headers, body: response.body}}"
end

begin
  require 'rest-client'

  server = $evm.object['server']
  port = $evm.object['port']
  token = $evm.get_state_var 'itsm_bmc_remedy_token'
  id = $evm.get_state_var 'itsm_bmc_remedy_change_id'
  
  status = 'Implementation In Progress' # TODO this should change to agreed success/failire/in-progress statuses
  status_reason = 'foo' # TODO this should to agreed descriptions for status
  pre_validation_result = $evm.object['itsm_change_pre_validation_result'] # TODO this should come provision outputs
  post_validation_result = $evm.object['itsm_change_post_validation_result'] # TODO this should come from provision outputs
  result = $evm.object['itsm_change_result'] # TODO this should come from provision outputs
  actual_start_date = $evm.object['itsm_change_actual_start_date'] # TODO this should come from provision outputs
  actual_end_date = $evm.object['itsm_change_actual_end_date'] # TODO this should come from provision outputs
  
  url = "https://#{server}:#{port}/api/arsys/v1/entry/CHG:Infrastructure Change/#{id}"
  payload = {
    values: {
      :'Change Request Status' => status,
      :'Status Reason' => status_reason,
      :'Pre-Imp. Validation Result' => pre_validation_result,
      :'Post-Imp Validation Result' => post_validation_result,
      :'Implementation Result' => result,
      :'Actual Start Date' => actual_start_date,
      :'Actual End Date' => actual_end_date
    }
  }.to_json
  
  response = RestClient::Request.execute method: :post,
                                         url: url,
                                         verify_ssl: false,
                                         headers: {
                                           Authorization: "AR-JWT #{token}",
                                           :'Content-Type' => 'application/json'
                                         },
                                         payload: payload
  log :info, response_to_s(response)
 
  exit MIQ_OK
rescue => err
  log :error, err_to_s(err)
  exit MIQ_ABORT
end
