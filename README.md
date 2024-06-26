# mix_systemd

This library generates a
[systemd](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
unit file to manage an Elixir application.

At its heart, it's a mix task which reads information about the project from
`mix.exs` plus optional library configuration in `config/config.exs` and
generates systemd unit files using Eex templates.

The goal is that the project defaults will generate a good systemd unit file,
and standard options support more specialized use cases. If you need more
customization, you can check the local copy of the templates into source
control and modify them (and patches are welcome).

It uses standard systemd functions and conventions to make your app
a more "native" OS citizen, and takes advantage of systemd features to improve
security and reliability.

While it can be used standalone, more advanced use cases require scripts
from e.g. [mix_deploy](https://github.com/cogini/mix_deploy).

Here is [a complete example app which uses mix_deploy](https://github.com/cogini/mix-deploy-example).

## Installation

Add `mix_systemd` to `deps` in `mix.exs`:

```elixir
{:mix_systemd, "~> 0.9.0"},
```

## Configuration

The library gets standard information in `mix.exs`, e.g. the app name and
version, then calculates default values for its configuration parameters.

You can override these parameters using settings in `config/config.exs`, e.g.:

```elixir
config :mix_systemd,
    app_user: "app",
    app_group: "app",
    base_dir: "/opt",
    env_vars: [
        "MY_VAR=true",
    ]
```

The library tries to choose smart defaults, so you may not need to configure
anything. See below for more options.

## Usage

The `systemd.init` task copies template files from `mix_systemd` into your
project, then the `systemd.generate` task uses them to create output files.

First, initialize templates under the `rel/templates/systemd` directory:

```shell
mix systemd.init
```

Next, generate output files under `_build/#{mix_env}/systemd/lib/systemd/system`.

```shell
MIX_ENV=prod mix systemd.generate
```

## Configuration options

The following sections describe configuration options.
See `lib/mix/tasks/systemd.ex` for all the details.

If you need to make changes not supported by the config options, then you can
check the templates into source control from `rel/templates/systemd` and make
your own changes.

### Basics

`app_name`: Elixir application name, an atom, from the `app` field in the `mix.exs` project.

`version`: `version` from the `mix.exs` project.

`ext_name`: External name, used for files and directories.
Default is `app_name` with underscores converted to "-".

`service_name`: Name of the systemd service, default `ext_name`.

`base_dir`: Base directory for app files on the target, default `/srv`

`deploy_dir`: Directory for app files on the target, default `#{base_dir}/#{ext_name}`

`app_user`: OS user account that the app runs under, default `ext_name`.

`app_group`: OS group account, default `ext_name`.

### Directories

We use the [standard app directories](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RuntimeDirectory=),
for modern Linux systems. App files under `/srv`, configuration under
`/etc`, transient files under `/run`, data under `/var/lib`.

Directories are named based on the app name, e.g. `/etc/#{ext_name}`.
The `dirs` variable specifies which directories the app uses, by default:

```elixir
dirs: [
  :runtime,       # App runtime files which may be deleted between runs, /run/#{ext_name}
                  # Used for RELEASE_TMP, RELEASE_MUTABLE_DIR, runtime-environment
  :configuration, # App configuration, e.g. db passwords, /etc/#{ext_name}
  # :state,       # App data or state persisted between runs, /var/lib/#{ext_name}
  # :cache,       # App cache files which can be deleted, /var/cache/#{ext_name}
  # :logs,        # App external log files, not via journald, /var/log/#{ext_name}
  # :tmp,         # App temp files, /var/tmp/#{ext_name}
],
```

Recent versions of systemd (after 235) will create these directories at
start time based on the settings in the unit file. For earlier systemd
versions, you need to create them beforehand using installation scripts, e.g.
[mix_deploy](https://github.com/cogini/mix_deploy).

For security, we set permissions more restrictively than the systemd defaults.
You can configure them with e.g. `configuration_directory_mode`. See the
defaults in `lib/mix/tasks/systemd.ex`.

`systemd_version`: Sets the systemd version on the target system, default 235.
This determines which systemd features the library will enable. If you are
targeting an older OS release, you may need to change it. Here are the systemd
versions in common OS releases:

* CentOS 7: 219
* Ubuntu 16.04: 229
* Ubuntu 18.04: 237

### Additional directories

The library uses a directory structure under `deploy_dir` which supports
multiple releases, similar to [Capistrano](https://capistranorb.com/documentation/getting-started/structure/).

* `scripts_dir`:  deployment scripts which e.g. start and stop the unit, default `bin`.
* `current_dir`: where the current Erlang release is unpacked or referenced by symlink, default `current`.
* `releases_dir`: where versioned releases are unpacked, default `releases`.
* `flags_dir`: dir for flag files to trigger restart, e.g. when `restart_method` is `:systemd_flag`, default `flags`.

When using multiple releases and symlinks, the deployment process works as follows:

1. Create a new directory for the release with a timestamp like
   `/srv/foo/releases/20181114T072116`.

2. Upload the new release tarball to the server and unpack it to the releases dir

3. Make a symlink from `/srv/#{ext_name}/current` to the new release dir.

4. Restart the app.

If you are only keeping a single version, then you would deploy it to
the `/srv/#{ext_name}/current` dir.

### Environment vars

The library sets a few common env vars in the unit file:

* `MIX_ENV`: `mix_env` var, default `Mix.env()`
* `LANG`: `env_lang` var, default `en_US.UTF-8`
* `RELEASE_TMP`: `runtime_dir`, e.g. `/run/#{ext_name}`
* `RUNTIME_DIR`: `runtime_dir`
* `DEPLOY_DIR`: `deploy_dir`
* `CONFIGURATION_DIR`: `configuration_dir`

You can set additional vars using the `env_vars` config var, e.g.:

```elixir
env_vars: [
    "MY_VAR=true",
]
```

The unit file also attempts to read environment vars from a series of files:

* `etc/environment` within the release, e.g. `/srv/app/currrent/etc/environment`
* `#{deploy_dir}/etc/environment`, e.g. `/srv/app/etc/environment`
* `#{configuration_dir}/environment`, e.g. `/etc/app/environment`
* `#{runtime_dir}/runtime-environment`, e.g. `/run/app/runtime-environment`

Later values override earlier values, so you can set defaults which get
overridden in the deployment or runtime environment.

### Systemd and OS

`limit_nofile`: Limit on open files, systemd
[LimitNOFILE](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#LimitCPU=),
default 65535.

`umask`: Process umask, systemd
[UMask](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#UMask=),
default 0027

`restart_sec`: Time to wait between restarts, systemd
[RestartSec](https://www.freedesktop.org/software/systemd/man/systemd.service.html#RestartSec=),
default 1 sec.

`service_type`: `:simple | :exec | :notify | :forking`. Default `:simple`.

Modern applications are not supposed to fork, they run in the foreground and
rely on the supervisor to manage them as a daemon. To do this, set
`service_type` to `:simple` or `:exec`. Note that in `simple` mode, systemd
doesn't actually check if the app started successfully, it just keeps going. If
something depends on your app being up, `:exec` may be better.

Set `service_type` to `:forking`, and this library sets `pid_file` to
`#{runtime_directory}/#{app_name}.pid` and sets the `PIDFILE` env var to tell
the boot scripts where it is.

The Erlang VM runs pretty well in foreground mode, but it is really expecting
to run as a standard Unix-style daemon, so forking might be better. Systemd
expects foregrounded apps to die when their pipe closes. See
https://elixirforum.com/t/systemd-cant-shutdown-my-foreground-app-cleanly/14581/2

`restart_method`: `:systemctl | :systemd_flag | :touch`. Default `:systemctl`

Set this to `:systemd_flag`, and the library will generate an additional
unit file which watches for changes to a flag file and restarts the
main unit. This allows updates to be pushed to the target machine by an
unprivileged user account which does not have permissions to restart
processes. `touch` the file `#{flags_dir}/restart.flag` and systemd will restart the unit.

### Runtime configuration

For configuration, we use a combination of build time settings, deploy
time settings, and runtime settings.

The configuration settings in `config/config.exs` are baked into the release.
We can then extend them with machine-specific configuration stored in the
configuration dir `/etc/#{ext_name}` which are read by the app on startup.

In on-premises deployments, we might generate the machine-specific
configuration once when setting up the app.

In cloud and other dynamic environments, we may run from a read-only image,
e.g. an Amazon AMI, which gets configured at start up based on the environment
by copying the config from an S3 bucket or a configuration store like
[AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-paramstore.html)
or etcd.

Some things change dynamically each time the app starts, e.g. the IP address of
the machine, or periodically, such as AWS access keys in an IAM instance role.

This library supports three ways to get runtime config:

#### `ExecStartPre` scripts

Scripts specified in `exec_start_pre` run before the main `ExecStart` script
runs, e.g.:

```elixir
exec_start_pre: [
"!/srv/foo/bin/deploy-sync-config-s3"
]
```

This runs the `deploy-sync-config-s3` script in `mix_deploy`, which
copies config files from an S3 bucket into `/etc/foo`. By default,
scripts run as the same user and group as the main script. Putting
`!` in front makes the script run with [elevated privileges](https://www.freedesktop.org/software/systemd/man/systemd.service.html#ExecStart=),
allowing it to write to `/etc/foo` even if the main script cannot for security reasons.

#### ExecStart wrapper script

Instead of running the main `ExecStart` script directly, you can run a shell script
which sets up the environment, then runs the main script with `exec`.
Set `exec_start_wrap` to the name of the script, e.g.
`deploy-runtime-environment-wrap` from `mix_deploy`.

This is redundant with `rel/env.sh.eex` in Elixir 1.9, but it runs earlier,
so it may still be useful.

#### Runtime environment service

You can run your own separate service to configure the runtime environment
before the app runs.  Set `runtime_environment_service_script` to a script such
as `deploy-runtime-environment-file` in `mix_deploy`.  The library will create
a `#{service_name}-runtime-environment.service` unit and make it a systemd
runtime dependency of the app.

### Runtime dependencies

Systemd starts units in parallel when possible, but we may need to enforce
ordering.  Set `unit_after_targets` to the names of systemd units that the
script depends on.  For example, if you are using cloud-init to get [runtime
network
information](https://cloudinit.readthedocs.io/en/latest/topics/network-config.html#network-configuration-outputs),
set:

```elixir
unit_after_targets: [
    "cloud-init.target"
]
```

## Security

`paranoia`: Enable systemd security options, default `false`.

    NoNewPrivileges=yes
    PrivateDevices=yes
    PrivateTmp=yes
    ProtectSystem=full
    ProtectHome=yes
    PrivateUsers=yes
    ProtectKernelModules=yes
    ProtectKernelTunables=yes
    ProtectControlGroups=yes
    MountAPIVFS=yes
                                                                                                    │
`chroot`: Enable systemd [chroot](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RootDirectory=), default `false`.
Sets systemd `RootDirectory` is set to `current_dir`. You can also set systemd [ReadWritePaths=, ReadOnlyPaths=,
InaccessiblePaths=](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ReadWritePaths=)
with the `read_write_paths`, `read_only_paths` and `inaccessible_paths` vars, respectively.
