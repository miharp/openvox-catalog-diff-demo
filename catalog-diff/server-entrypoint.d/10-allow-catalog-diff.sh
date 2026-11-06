#!/bin/bash
# Let the Catalog Diff node compile catalogs for other nodes through the
# certless v4 catalog API. Same approach as the image's own
# 88-add_cache_del_api_auth_rules.rb.

set -e

auth_conf=/etc/puppetlabs/puppetserver/conf.d/auth.conf
certname="${CATALOG_DIFF_CERTNAME:-catalog-diff}"

if grep -q 'puppetlabs certless catalog' "$auth_conf"; then
  echo 'Certless catalog rule already set'
  exit 0
fi

AUTH_CONF="$auth_conf" CERTNAME="$certname" /opt/puppetlabs/puppet/bin/ruby <<'RUBY'
require 'hocon'
require 'hocon/parser/config_document_factory'
require 'hocon/config_value_factory'

auth_conf = ENV.fetch('AUTH_CONF')
rules = Hocon.load(auth_conf)['authorization']['rules']
rules << {
  'match-request' => {
    'path'   => '^/puppet/v4/catalog',
    'type'   => 'regex',
    'method' => ['post'],
  },
  'allow'      => [ENV.fetch('CERTNAME')],
  'sort-order' => 500,
  'name'       => 'puppetlabs certless catalog',
}

doc = Hocon::Parser::ConfigDocumentFactory.parse_file(auth_conf)
doc = doc.set_config_value('authorization.rules', Hocon::ConfigValueFactory.from_any_ref(rules))
File.write(auth_conf, doc.render)
RUBY

echo "Allowed ${certname} to use the certless catalog API"
