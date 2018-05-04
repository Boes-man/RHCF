def log(level, message)
  method = 'ldap_active_directory_group_query'
  $evm.log level, "#{method} - #{message}"
end

def err_to_s(err)
  "[#{err}]\n#{err.backtrace.join '\n'}"
end

begin
  require 'net/ldap'
  @task = $evm.root['miq_request']
    ### BEGIN CONFIGURATION ###
    SERVER = $evm.object['ldap_host']   # Active Directory server name or IP
    PORT = $evm.object['ldap_port']                    # Active Directory server port (default 389)
    BASE = $evm.object['ldap_base']    # Base to search from
    DOMAIN = $evm.object['ldap_domain']        # For simplified user@domain format login
    login = $evm.object['ldap_svcuser']
    pass = $evm.object.decrypt('ldap_pass')
    SSL = ':simple_tls'
    user = @task.userid.split('@').first
 #   u = usr.split("@")
 #   user = u[0]
    group = @task.get_option(:dialog)['dialog_cx_project_id'].to_s.downcase
    ### END CONFIGURATION ###

      conn = Net::LDAP.new :host => SERVER,
                           :port => PORT,
                           :base => BASE,
                           :encryption => SSL,
                           :auth => { :username => "#{login}@#{DOMAIN}",
                                      :password => pass,
                                      :method => :simple }
      if conn.bind
        log(:info, "LDAP bind success")
        filter  = "(&(cn=*)(sAMAccountName=#{user}))"
        conn.search(:base => "#{BASE}", :filter => "#{filter}") do |object|
          @results = object.memberOf.to_s.downcase
          if @results.include? "#{group}," then
            project_ad = true
            log(:info, "CPACF: AD Check Success: #{user} is a member of #{group}")
           else
            log(:info, "CPACF: AD Check Fail: #{user} not found in #{group}")
            
            $evm.root['ae_result'] = 'error'
            $evm.root['ae_reason'] = "User with ID '#{user}' not a member of the '#{group}' group on ActiveDirectory server (#{SERVER})"

            exit MIQ_ABORT
          end
         end
       else
        log(:info, "CPACF: LDAP bind failed")
        exit MIQ_ABORT
       end
 rescue => err      
  log :error, err_to_s(err)
  exit MIQ_ABORT
end
