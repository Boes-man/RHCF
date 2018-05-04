def log(level, message)
  method = 'itsm_bmc_remedy_project_query'
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
  id = 'ADO38575' #prov.get_option(:dialog)['dialog_cx_project_id'] # TODO verify this succeeds or fails
  
  url = "https://#{server}:#{port}/api/arsys/v1/entry/CX:CHG:ProjectIdName_ETE"
  params = {
    q: "'Project ID'" + (id ? ('="' + id + '"') : '!=$NULL$'),
    fields: 'values'
  }
  values = '(Project ID, Project Name, Project Manager, Project Manager Email)'

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

  entries = JSON.parse(response.body)['entries']
  if !entries || !entries.size
    $evm.root['ae_result'] = 'error'
    
    if id
      $evm.root['ae_reason'] = "Project with ID '#{id}' not found on BMC Remedy server (#{id})"
    else
      $evm.root['ae_reason'] = "No projects found on BMC Remedy server (#{id})"
    end
    
    exit MIQ_ABORT
  end
  
  info = nil
  if id
    info = entries[0]['values']
  else
    info = entries.map do |entry|
      entry['values']
    end
  end
  
  log :info, "Setting state variable {'itsm_bmc_remedy_project_info' => #{info}}"
  $evm.set_state_var 'itsm_bmc_remedy_project_info', info # TODO this may not suit the all project use-case
  
  exit MIQ_OK
  
rescue => err
  log :error, err_to_s(err)
  
  exit MIQ_ABORT
end
