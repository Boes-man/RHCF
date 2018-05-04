def log(level, message)
  method = 'itsm_bmc_remedy_logout'
  $evm.log level, "#{method} - #{message}"
end

def err_to_s(err)
  "[#{err}]\n#{err.backtrace.join '\n'}"
end

def response_to_s(response)
  "Response #{{code: response.code, headers: response.headers, body: response.body}}"
end

begin
  require 'rest-client'
  
  server = $evm.object['server']
  port = $evm.object['port']
  token = $evm.get_state_var 'itsm_bmc_remedy_token'
  
  url = "https://#{server}:#{port}/api/jwt/logout"
  response = RestClient::Request.execute method: :post,
                                         url: url,
                                         verify_ssl: false,
                                         headers: {
                                           Authorization: "AR-JWT #{token}"
                                         }
  log :info, response_to_s(response)

rescue => err
  log :warn, err_to_s(err)
ensure
  exit MIQ_OK
end

