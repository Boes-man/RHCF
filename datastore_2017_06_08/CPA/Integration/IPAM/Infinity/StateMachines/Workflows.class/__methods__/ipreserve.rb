def log(level, message)
  method = 'ipam_fusionlayer_infinity_network_ip_reserve'
  $evm.log level, "#{method} - #{message}"
end

def err_to_s(err)
  "[#{err}]\n#{err.backtrace.join '\n'}"
end

def response_to_s(response)
  "Response #{{code: response.code, headers: response.headers, body: response.body}}"
end

begin
  def reserve_ip(network_id)
    require 'rest-client'

    begin
      params = {
        method: :post,
        url: "https://#{@server}:#{@port}/rest/v1/networks/#{network_id}/reserveip",
        headers: {
          Accept: 'application/json'
        },
        verify_ssl: false,
        user: @user,
        password: @password
      }
      response = RestClient::Request.execute params
      log :info, response_to_s(response)
    rescue RestClient::Exception => err
      log :warn, err_to_s(err)
      return
    else
      JSON.parse(response.body).first
    end
  end

  @server = $evm.object['ipam_server']
  @port = $evm.object['ipam_port']
  @user = $evm.object['ipam_user']
  @password = $evm.object.decrypt 'ipam_password'
  network_ids = $evm.get_state_var 'ipam_fusionlayer_infinity_network_ids'

  ip_info = nil
  network_ids.each do |network_id|
    ip_info = reserve_ip network_id
    break ip_info if ip_info
  end
  raise "Unable to reserve IP address from specified networks: #{network_ids}" unless ip_info
  
  ip_address = ip_info['address']
  log :info, "Setting miq_provision attribute {'ip_addr' => #{ip_address}}"
  $evm.root['miq_provision'].set_option :ip_addr, ip_address
  ip_address_id = ip_info['id']
  log :info, "Setting state variable {'ipam_fusionlayer_infinity_ip_address_id' => #{ip_address_id}}"
  $evm.set_state_var 'ipam_fusionlayer_infinity_ip_address_id', ip_address_id
  exit MIQ_OK
  
rescue => err
  log :error, err_to_s(err)
  exit MIQ_ABORT
end
