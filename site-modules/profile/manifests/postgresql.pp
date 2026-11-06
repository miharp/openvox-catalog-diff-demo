# @summary Installs and configures PostgreSQL
#
# @param max_connections
#   Maximum number of concurrent connections
class profile::postgresql (
  Integer[1] $max_connections,
) {
  package { 'postgresql':
    ensure => installed,
  }

  file { '/etc/postgresql/conf.d/tuning.conf':
    ensure  => file,
    owner   => 'postgres',
    group   => 'postgres',
    mode    => '0644',
    content => "max_connections = ${max_connections}\n",
    require => Package['postgresql'],
    notify  => Service['postgresql'],
  }

  service { 'postgresql':
    ensure => running,
    enable => true,
  }
}
