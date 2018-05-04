def log(level, message)    
  method = 'itsm_bmc_remedy_login'
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
  user = $evm.object['user']
  password = $evm.object.decrypt 'password'

  url = "https://#{server}:#{port}/api/jwt/login"
  payload = {
    username: user,
    password: password
  }
  response = RestClient::Request.execute method: :post,
                                         url: url,
                                         verify_ssl: false,
                                         payload: payload
  log :info, response_to_s(response)
  $evm.set_state_var 'itsm_bmc_remedy_token', response.body
  exit MIQ_OK
  
rescue => err
  log :error, err_to_s(err)
  exit MIQ_ABORT
end
