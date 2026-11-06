# @summary A database server
class role::database {
  include profile::base
  include profile::postgresql
}
