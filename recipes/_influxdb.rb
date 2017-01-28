my_private_ip = my_private_ip()


template"#{node.influxdb.conf_dir}/influxdb.conf" do
  source "influxdb.conf.erb"
  owner node.hopsmonitor.user
  group node.hopsmonitor.group
  mode 0650
  variables({ 
     :my_ip => my_private_ip
           })
end

case node.platform
when "ubuntu"
 if node.platform_version.to_f <= 14.04
   node.override.influxdb.systemd = "false"
 end
end


service_name="influxdb"

if node.influxdb.systemd == "true"

  service service_name do
    provider Chef::Provider::Service::Systemd
    supports :restart => true, :stop => true, :start => true, :status => true
    action :nothing
  end

  case node.platform_family
  when "rhel"
    systemd_script = "/usr/lib/systemd/system/#{service_name}.service" 
  when "debian"
    systemd_script = "/lib/systemd/system/#{service_name}.service"
  end

  template systemd_script do
    source "#{service_name}.service.erb"
    owner "root"
    group "root"
    mode 0754
    notifies :enable, resources(:service => service_name)
    notifies :start, resources(:service => service_name), :immediately
  end

  kagent_config "reload_influxdb_daemon" do
    action :systemd_reload
  end  

else #sysv

  service service_name do
    provider Chef::Provider::Service::Init::Debian
    supports :restart => true, :stop => true, :start => true, :status => true
    action :nothing
  end

  template "/etc/init.d/#{service_name}" do
    source "#{service_name}.erb"
    owner node.hopsmonitor.user
    group node.hopsmonitor.group
    mode 0754
    notifies :enable, resources(:service => service_name)
    notifies :restart, resources(:service => service_name), :immediately
  end

end


# case node.platform_family
#   when "debian"
#     package "ruby-dev"
#   when "rhel"
#     package "ruby-devel" 
# end

include_recipe 'influxdb::ruby_client'

dbname = 'graphite'

# Create a test database
influxdb_database dbname do
  action :create
end


# Create a test user and give it access to the test database
influxdb_user node.influxdb.db_user do
  password node.influxdb.db_password
  databases [dbname]
  api_hostname my_private_ip
  api_port 8086
  use_ssl false
  verify_ssl false
  action :create
end

# Create a test cluster admin
influxdb_admin node.influxdb.admin_user do
  password node.influxdb.admin_password
  action :create
end


# Create a test retention policy on the test database
influxdb_retention_policy 'test_policy' do
  policy_name 'one_week'
  database dbname
  duration '1w'
  replication 1
  # by default in v1.0 there's a policy named autogen that is created for any
  # db, when `meta.retention-autocreate`=true. We will make this test_policy
  # the default policy.
  # ref1: https://docs.influxdata.com/influxdb/v1.0/query_language/database_management/#retention-policy-management
  # ref2: https://docs.influxdata.com/influxdb/v1.0/administration/config/#meta
  default true
  action :create
  notifies :restart, 'service[influxdb]'
end


if node.kagent.enabled == "true" 
   kagent_config "influxdb" do
     service "influxdb"
     log_file "/var/log/influxdb.log"
   end
end

