# Nodes are classified by the pp_role extension in their certificate.
node default {
  $role = $trusted['extensions']['pp_role']

  if $role {
    include "role::${role}"
  } else {
    include profile::base
  }
}
