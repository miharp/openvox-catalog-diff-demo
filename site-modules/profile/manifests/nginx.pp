# @summary Installs and configures nginx
#
# @param worker_connections
#   Maximum simultaneous connections per worker process
# @param server_names
#   Names the default server answers to
class profile::nginx (
  Integer[1] $worker_connections,
  Array[String[1]] $server_names = ['_'],
) {
  package { 'nginx':
    ensure => installed,
  }

  file { '/etc/nginx/nginx.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('profile/nginx/nginx.conf.epp', {
        'worker_connections' => $worker_connections,
        'server_names'       => $server_names,
    }),
    require => Package['nginx'],
    notify  => Service['nginx'],
  }

  # From the Puppetfile: restart nginx when it dies.
  systemd::dropin_file { 'restart.conf':
    unit    => 'nginx.service',
    content => "[Service]\nRestart=on-failure\n",
    notify  => Service['nginx'],
  }

  service { 'nginx':
    ensure => running,
    enable => true,
  }
}
