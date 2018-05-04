def log(level, message)
  method = 'itsm_bmc_remedy_change_query'
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
  module RestClient
    class Request
      def append_to_querystring(string)
        @uri.query += string
      end
    end
    module Utils
      def self.escape(string)
        require 'erb'
        ERB::Util.url_encode string
      end
    end
  end

  server = $evm.object['server']
  port = $evm.object['port']
  token = $evm.get_state_var 'itsm_bmc_remedy_token'
  id = $evm.get_state_var 'itsm_bmc_remedy_change_id'
  
  url = "https://#{server}:#{port}/api/arsys/v1/entry/CHG:Infrastructure Change"
  params = {
    q: "'Infrastructure Change ID'=\"#{id}\"",
    fields: 'values'
  }
  values = '(Request ID, Change Request Status, Scheduled Start Date, Scheduled End Date)'

  request = RestClient::Request.new method: :get,
                                    url: url,
                                    verify_ssl: false,
                                    headers: {
                                      Authorization: "AR-JWT #{token}",
                                      Accept: 'application/json',
                                      params: params
                                    }
  request.append_to_querystring values

  response = request.execute
  log :info,  response_to_s(response)

  info = JSON.parse(response.body)['values']
  log :info, "Setting state variable {'itsm_bmc_remedy_change_info' => #{info}}"
  $evm.set_state_var 'itsm_bmc_remedy_change_info', info
  
  exit MIQ_OK
rescue => err
  log :error, err_to_s(err)
  
  exit MIQ_ABORT
end
