# Catalog diff demo

A small OpenVox control repo that shows which nodes a pull request would change, and how.
Each pull request gets a comment listing the nodes whose catalogs differ from the base branch,
with the resource and file content differences for each. Pull requests from forks get the same
report as a job summary.

It uses [Catalog Diff](https://github.com/voxpupuli/puppet-catalog_diff) against a throwaway
OpenVox server and OpenVoxDB that live only for the length of the job, so it runs on
GitHub-hosted runners and needs no access to real infrastructure.

## How it works

`catalog-diff/run.sh BASE_REF HEAD_REF` does the following:

1. Deploys `BASE_REF` as the `production` environment and `HEAD_REF` as the `change` environment.
2. Starts an OpenVox server, OpenVoxDB, and PostgreSQL from the
   [OpenVox container images](https://github.com/OpenVoxProject?q=container), based on the
   [CRAFTY minimal stack](https://github.com/voxpupuli/crafty/tree/main/openvox/minimal).
3. Starts three agents: `web01`, `web02`, and `db01`. Each one requests a `pp_role` certificate
   extension, and `manifests/site.pp` includes the matching role.
4. Runs each agent once in noop mode. That records its facts in OpenVoxDB without changing
   anything in the container.
5. Enrolls a separate `catalog-diff` node and runs `puppet catalog diff` from it. The server
   compiles every node's catalog twice through its certless catalog API, once from
   `production` and once from `change`, using the facts stored in OpenVoxDB.
6. Prints a summary, and writes the JSON report and Catalog Diff's full output to
   `catalog-diff/.work/report/`.

`catalog-diff/summary.py` writes that summary from the report, as text for the terminal or as
the Markdown the workflow posts. Nodes that change in the same way are listed together.

## Try it locally

You need Docker with Compose, and Git.

```console
catalog-diff/run.sh production tune-nginx
```

Set `KEEP=1` to leave the stack running afterwards.

## Server setup the diff depends on

The scripts in `catalog-diff/server-entrypoint.d/` and the settings in
`catalog-diff/compose.yaml` configure what Catalog Diff needs. A real server needs the same things:

- An `auth.conf` rule that lets the `catalog-diff` certificate use the certless catalog API
  (`/puppet/v4/catalog`).
- The `catalog-diff` certificate on the OpenVoxDB certificate allowlist, if you use one.
- OpenVoxDB as the server's facts terminus in `routes.yaml`. The certless API reads each node's
  trusted facts from there.
- `openvoxdb-termini` and a `puppetdb.conf` on the node that runs the diff.

## Use it against your own servers

The same command runs against a real server from a machine inside your network, such as a
self-hosted runner. The nodes are then your real ones, with their own facts.

I ran it that way in a lab on 2026-11-06: OpenVox Server and OpenVoxDB 8.18.0, three nodes on
AlmaLinux 9, AlmaLinux 10 and Ubuntu 24.04, and the diff run by hand from one of the agents.
Registering that machine as a GitHub runner and driving it from a workflow is not tested yet.

The OpenVox docs' [Impact Analysis](https://docs.openvoxproject.org/ecosystem/latest/devkit/impact_analysis.html)
page covers the `auth.conf` rule and the OpenVoxDB allowlist. Until the rule is there the
server answers `403 Forbidden request: /puppet/v4/catalog`. The rest is below.

**On the server**

- OpenVoxDB has to be the facts terminus in `routes.yaml`. A server connected to OpenVoxDB with
  the `openvoxdb` module already has that.
- The branch under test has to be deployed as an environment. r10k does that for every branch
  of a control repo; the job has to run after that deploy, or trigger it.

**On the runner**

- The `openvox-agent` and `openvoxdb-termini` packages, and network access to the server on 8140
  and to OpenVoxDB on 8081.
- An unprivileged user with a certificate of its own. Never run the agent under that name, so
  it does not become a node:

  ```console
  puppet ssl bootstrap --certname catalog-diff --server puppet.example.com
  ```

- A `puppetdb.conf` in that user's confdir (`puppet config print confdir`):

  ```ini
  [main]
  server_urls = https://puppet.example.com:8081
  ```

- The module: `puppet module install puppet-catalog_diff`.

**The diff**

```console
puppet catalog diff \
  puppet.example.com:8140/production puppet.example.com:8140/my_branch \
  --certname catalog-diff --filter_old_env --certless \
  --show_resource_diff --content_diff \
  --output_report report.json
catalog-diff/summary.py --text report.json
```

What the lab run showed:

- One version bump in Hiera came out as a different package version on each operating system
  (`-1.el9`, `-1.el10`, `-1+ubuntu24.04`), and as an extra changed resource on Ubuntu only.
- It only reads. The nodes' stored catalogs, facts and trusted facts were the same before and
  after, and the runner's certificate did not show up as a node.
- Compile both catalogs, as the command above does. With `--old_catalog_from_puppetdb` the old
  catalog is the one the node last received, but OpenVoxDB stores it without Sensitive values,
  so every resource that has one is reported as changed: 10 of them across three nodes here.
- Three nodes, six compiles, took 22 seconds.

Catalog Diff only looks at nodes whose `kernel` fact is `Linux` unless you pass `--fact_search`
or `--node_list`, and `--threads` sets how many catalogs it asks for at once. See its
[README](https://github.com/voxpupuli/puppet-catalog_diff#usage).

Only use self-hosted runners on private repositories. On a public one, a pull request from a
fork can run code on the runner, which holds a certificate your server trusts.
