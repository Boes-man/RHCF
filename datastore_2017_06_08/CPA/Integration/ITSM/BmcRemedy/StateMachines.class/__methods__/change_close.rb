def log(level, message)
  method = 'itsm_bmc_remedy_change_close'
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
  
  status = 'Implementation In Progress' # TODO change to agree rememdy 'close' state
  status_reason = 'Foo' # TODO change to agree desciption for closing chagne
  
  url = "https://#{server}:#{port}/api/arsys/v1/entry/CHG:Infrastructure Change/#{id}"
  payload = {
    values: {
      :'Change Request Status' => status,
      :'Status Reason' => status_reason
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
