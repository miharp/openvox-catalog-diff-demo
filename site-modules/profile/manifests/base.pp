# @summary Settings every node gets
#
# @param motd
#   Content of /etc/motd
class profile::base (
  String[1] $motd,
) {
  file { '/etc/motd':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => $motd,
  }

  package { 'chrony':
    ensure => installed,
  }

  service { 'chrony':
    ensure  => running,
    enable  => true,
    require => Package['chrony'],
  }
}
