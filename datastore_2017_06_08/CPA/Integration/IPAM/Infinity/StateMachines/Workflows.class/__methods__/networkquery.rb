def log(level, message)
  method = 'ipam_fusionlayer_infinity_network_query'
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

  server = $evm.object['ipam_server']
  port = $evm.object['ipam_port']
  user = $evm.object['ipam_user']
  password = $evm.object.decrypt 'ipam_password'

  prov = $evm.root['miq_provision']
  site = prov.options[:data_center]
  env = prov.options[:envname]
  zone = prov.options[:zone]
  use = $evm.object['vm_network_usage'] # TODO why not an option?
  
  infos = {
    infos: {
      Site: site,
      Environment: env,
      Zone: zone,
      Usage: use
    }
  }.to_json
  params = {
    method: :get,
    url: "https://#{server}:#{port}/rest/v1/search",
    headers: {
      Accept: 'application/json',
      params: {
        query: {}
      }
    },
    verify_ssl: false,
    user: user,
    password: password
  }

  request = RestClient::Request.new params
  request.append_to_querystring "=#{infos}"
  response = request.execute
  log :info, response_to_s(response)
  body = JSON.parse(response.body)
  network_ids = (body.is_a? Array) ? body.map {|network| network['id']} : [body['id']]
  log :info, "Setting state variable {'ipam_fusionlayer_infinity_network_ids' => #{network_ids}}"
  $evm.set_state_var 'ipam_fusionlayer_infinity_network_ids', network_ids
  exit MIQ_OK

rescue => err
  log :error, err_to_s(err)
  exit MIQ_ABORT
end
