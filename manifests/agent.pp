# Class: puppet::agent
#
# This class installs and configures the puppet agent
#
# Parameters:
#   ['puppet_server']         - The dns name of the puppet master
#   ['puppet_server_port']    - The Port the puppet master is running on
#   ['puppet_agent_service']  - The service the puppet agent runs under
#   ['puppet_agent_package']  - The name of the package providing the puppet agent
#   ['version']               - The version of the puppet agent to install
#   ['puppet_run_style']      - The run style of the agent either cron or service
#   ['puppet_run_interval']   - The run interval of the puppet agent in minutes, default is 30 minutes
#   ['user_id']               - The userid of the puppet user 
#   ['group_id']              - The groupid of the puppet group
#   ['splay']                 - If splay should be enable defaults to false
#   ['environment']           - The environment of the puppet agent
#
# Actions:
# - Install and configures the puppet agent
#
# Requires:
# - Inifile
#
# Sample Usage:
#   class { 'puppet::agent':
#       puppet_server             => master.puppetlabs.vm,
#       environment               => production,
#       splay                     => true,
#   }
#
class puppet::agent(
  $puppet_server          = $::puppet::params::puppet_server,
  $puppet_server_port     = $::puppet::params::puppet_server_port,
  $puppet_agent_service   = $::puppet::params::puppet_agent_service,
  $puppet_agent_package   = $::puppet::params::puppet_agent_package,
  $version                = 'present',
  $puppet_run_style       = 'service',
  $puppet_run_interval    = 30,
  $user_id                = undef,
  $group_id               = undef,
  $splay                  = false,
  $environment            = 'production'
) inherits puppet::params {

  if ! defined(User[$::puppet::params::puppet_user]) {
    user { $::puppet::params::puppet_user:
      ensure => present,
      uid    => $user_id,
      gid    => $::puppet::params::puppet_group,
    }
  }

  if ! defined(Group[$::puppet::params::puppet_group]) {
    group { $::puppet::params::puppet_group:
      ensure => present,
      gid    => $group_id,
    }
  }
  package { $puppet_agent_package:
    ensure   => $version,
  }

  if $puppet_run_style == 'service'
  {
    $startonboot = 'yes'
  }
  else {
    $startonboot = 'no'
  }

  if $::kernel == 'Linux' and $startonboot == 'yes' {
    file { $puppet::params::puppet_defaults:
      mode    => '0644',
      owner   => 'root',
      group   => 'root',
      require => Package[$puppet_agent_package],
    }

    case $::operatingsystem {
      'centos', 'redhat', 'fedora': {
        ini_setting {'redhatpuppetserver':
          ensure  => present,
          section => '',
          setting => 'PUPPET_SERVER',
          path    => $puppet::params::puppet_defaults,
          value   => $puppet_server,
          require => File[$puppet::params::puppet_defaults],
        }
        ini_setting {'redhatpuppetport':
          ensure  => present,
          section => '',
          setting => 'PUPPET_PORT',
          path    => $puppet::params::puppet_defaults,
          value   => $puppet_server,
          require => File[$puppet::params::puppet_defaults],
        }
      }
      'ubuntu', 'debian': {
        ini_setting {'debianpuppetautostart':
          ensure  => present,
          section => '',
          setting => 'START',
          path    => $puppet::params::puppet_defaults,
          value   => $startonboot,
          require => File[$puppet::params::puppet_defaults],
        }
      }
    }
  }

  if ! defined(File[$::puppet::params::confdir]) {
    file { $::puppet::params::confdir:
      ensure  => directory,
      require => Package[$puppet_agent_package],
      owner   => $::puppet::params::puppet_user,
      group   => $::puppet::params::puppet_group,
      notify  => Service[$puppet_agent_service],
    }
  }

  case $puppet_run_style {
    'service': {
          $service_notify = Service[$puppet_agent_service]
          service { $puppet_agent_service:
            ensure    => true,
            enable    => true,
            require   => File [$::puppet::params::puppet_conf],
            subscribe => Package[$puppet_agent_package],
            }
    }
    'cron': {
      # ensure that puppet is not running and will start up on boot
      service { $puppet_agent_service:
        ensure      => 'stopped',
        enable      => false,
        hasrestart  => true,
        hasstatus   => true,
        require     => Package[$puppet_agent_package],
      }

      # Run puppet as a cron - this saves memory and avoids the whole problem
      # where puppet locks up for no reason. Also spreads out the run intervals
      # more uniformly.
      $time1  =  fqdn_rand($puppet_run_interval)
      $time2  =  fqdn_rand($puppet_run_interval) + 30

      cron { 'puppet-client':
        command => '/usr/bin/puppet agent --no-daemonize --onetime --logdest syslog > /dev/null 2>&1',
        user    => 'root',
        # run twice an hour, at a random minute in order not to collectively stress the puppetmaster
        hour    => '*',
        minute  => [ $time1, $time2 ],
      }
    }
    default: {
      err 'Unsupported puppet run style in Class[\'puppet::agent\']'
    }
  }

  if ! defined(File[$::puppet::params::puppet_conf]) {
      file { $::puppet::params::puppet_conf:
        ensure  => 'file',
        mode    => '0644',
        require => File[$::puppet::params::confdir],
        owner   => $::puppet::params::puppet_user,
        group   => $::puppet::params::puppet_group,
        notify  => $service_notify,
      }
    }
    else {
      if $puppet_run_style == 'service' {
        File<| title == $::puppet::params::puppet_conf |> {
          notify  +> $service_notify,
        }
      }
    }

  #run interval in seconds
  $runinterval = $puppet_run_interval * 60

  ini_setting {'puppetagentmaster':
    ensure  => present,
    section => 'agent',
    setting => 'server',
    path    => $::puppet::params::puppet_conf,
    value   => $puppet_server,
    require => File[$::puppet::params::puppet_conf],
  }

  ini_setting {'puppetagentenvironment':
    ensure  => present,
    section => 'agent',
    setting => 'environment',
    path    => $::puppet::params::puppet_conf,
    value   => $environment,
    require => File[$::puppet::params::puppet_conf],
  }

  ini_setting {'puppetagentruninterval':
    ensure  => present,
    section => 'agent',
    setting => 'runinterval',
    path    => $::puppet::params::puppet_conf,
    value   => $runinterval,
    require => File[$::puppet::params::puppet_conf],
  }

  ini_setting {'puppetagentsplay':
    ensure  => present,
    section => 'agent',
    setting => 'splay',
    path    => $::puppet::params::puppet_conf,
    value   => $splay,
    require => File[$::puppet::params::puppet_conf],
  }

  ini_setting {'puppetmasterport':
    ensure  => present,
    section => 'agent',
    setting => 'masterport',
    path    => $::puppet::params::puppet_conf,
    value   => $puppet_server_port,
    require => File[$::puppet::params::puppet_conf],
  }
}
