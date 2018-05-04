def log(level, message)
  method = 'itsm_bmc_remedy_change_create'
  $evm.log level, "#{method} - #{message}"
end

def err_to_s(err)
  "[#{err}]\n#{err.backtrace.join '\n'}"
end

def response_to_s(response)
  "Rresponse #{{code: response.code, headers: response.headers, body: response.body}}"
end

begin
  ENV['RESTCLIENT_LOG'] = 'stdout'
  
  require 'time'
  require 'rest-client'

  server = $evm.object['server']
  port = $evm.object['port']
  token = $evm.get_state_var 'itsm_bmc_remedy_token'
  
  prov = $evm.root['miq_request']
  requestor_id = 'Testuser' # prov.userid.split('@').first -- this fails if it doesnt exist in remedy
  template_id = 'VM Provision' 
  env = prov.get_option(:dialog)['dialog_itsm_env']
  status = 'Implementation In Progress'
  cx_project_id = 'ADO38575' #prov.get_option(:dialog)['dialog_cx_project_id'] # TODO verify this succeeds or fails
  scheduled_start_date = Time.now().gmtime + 60 # TODO this should marry with evm scheduled (request task) start date
  scheduled_end_date = scheduled_start_date + 60 * 60 * 5
  
  url = "https://#{server}:#{port}/api/arsys/v1/entry/CHG:ChangeInterface_Create"
  payload = {
    values: {
      :'Requestor ID' => requestor_id,
      TemplateID: template_id,
      Environment: env,
      Status: status,
      :'CX_Project ID' => cx_project_id,
      :'Scheduled Start Date' => scheduled_start_date.iso8601(3).chop + '+0000', # TODO refactor to remove dup
      :'Scheduled End Date' => scheduled_end_date.iso8601(3).chop + '+0000'
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
  location = response.headers[:location].split('/').last
  $evm.set_state_var 'itsm_bmc_remedy_change_location', location
  exit MIQ_OK

rescue => err
  log :error, err_to_s(err)
  exit MIQ_ABORT
end
