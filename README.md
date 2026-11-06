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
4. Runs each agent once in noop mode. That records its facts and its `production` catalog in
   OpenVoxDB without changing anything in the container.
5. Enrolls a separate `catalog-diff` node and runs `puppet catalog diff` from it. The old catalogs
   come from OpenVoxDB. The new ones are compiled for the `change` environment through the
   server's certless catalog API, using the facts stored in OpenVoxDB.
6. Writes a JSON report to `catalog-diff/.work/report/report.json`.

`catalog-diff/summary.py` turns the report into the Markdown that the workflow posts.

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

The same `puppet catalog diff` command works against a real OpenVox server from a runner inside
your network. In that setup the old catalogs are the ones your nodes last received, and the branch
under test must be deployed as an environment first. Only use self-hosted runners on private
repositories.
