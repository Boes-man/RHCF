begin
  def log(level, message)
    method = 'ipam_infinity_network_ip_release'
    $evm.log level, "#{method} - #{message}"
  end

  def err_to_s(err)
    "[#{err}]\n#{err.backtrace.join '\n'}"
  end

  def response_to_s(response)
    "Response #{{code: response.code, headers: response.headers, body: response.body}}"
  end

  @server = $evm.object['ipam_server']
  @port = $evm.object['ipam_port']
  @user = $evm.object['ipam_user']
  @password = $evm.object.decrypt('ipam_password')

  id = $evm.root['vm'].custom_get :ipam_ip_address_id

  require 'rest-client'
  url = "https://#{server}:#{port}/rest/v1/ip_addresses/#{id}"
  params = {
    method: :delete,
    url: url,
    headers: {
      Accept: 'application/json'
    },
    verify_ssl: false,
    user: user,
    password: password
  }
  response = RestClient::Request.execute params
  log :info, response
  exit MIQ_OK

rescue => err
  log :error, err_to_s(err)
  exit MIQ_ABORT
end
