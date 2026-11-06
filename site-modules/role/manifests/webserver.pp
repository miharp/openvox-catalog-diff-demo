# @summary A web server
class role::webserver {
  include profile::base
  include profile::nginx
}
