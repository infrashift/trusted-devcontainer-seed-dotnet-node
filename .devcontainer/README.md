# .devcontainer

Two things in one image, and the split is deliberate — see the header comment in
`Containerfile`.

## What came from the trusted template

    template:  ghcr.io/infrashift/trusted-devcontainer-templates/dotnet-node
    version:   v1.0.1

`devcontainer.json`'s eleven `features` and the `FROM` line are that template,
digest-pinned and unmodified. A `devcontainer.json` cannot *reference* a
template at build time -- a template is applied, and what it produced is what
is committed here -- so the provenance is recorded above and regenerated with:

    devcontainer templates apply \
      --template-id ghcr.io/infrashift/trusted-devcontainer-templates/dotnet-node

`scripts/test.sh` proves every reference is still digest-pinned.

## What this repository added, and why each one

| Addition | Why |
| --- | --- |
| `containerUser: user` (uid 1001, **gid 0**) | The template creates `dev` (1001:1001). The platform contract is `user` in group 0, assumed by the portal's `WORKSPACE_SSH_USER`, `sshd_config`, the jobspec's volume-init chown and `/home/user/workspace` in the portal README |
| `openssh-server` | Not in the trusted base. Its absence is a workspace that starts, reports its container healthy, and refuses every connection |
| `entrypoint.sh`, `config/sshd_config`, `config/ssh-login.sh` | The workspace runtime contract — the third is the `ForceCommand` the second names |
| `workspace-skel/` | Copied into an EMPTY host volume by the jobspec's prestart task |
| `/etc/profile.d/dotnet-node.sh` | The `dotnet`, `nodejs` and `pnpm` features install under `~/.local/share/<tool>` and declare `DOTNET_ROOT`, `PNPM_HOME` and `PATH` with `/home/dev` written in; this renders them on `$HOME` for the SSH login shell, which sshd would otherwise start without them |
| *(no database client)* | Neither `psql` nor `sqlcmd`. `psql` left with the PostgreSQL companion: verify check 8 runs only when a workspace declares **no** companion service, and this seed declares one, so the built-in demo database is never deployed beside it. `sqlcmd` is not added in its place — the companion's health check runs inside its own container, where Microsoft's image already carries one, and a client here would mean admitting `packages.microsoft.com` through the egress allow-list. .NET reaches SQL Server through `Microsoft.Data.SqlClient` |
## What the image carries, for the devpod verify

`make verify` in the devpod root asks the image which tools it declares
(check 6). This image's list:

    WORKSPACE_TOOLS=dotnet,node,npm,pnpm,jq,yq,git,git-lfs,syft,grype

## The three copies

`entrypoint.sh`, `config/sshd_config` and `config/ssh-login.sh` are copies of
`terraform/live/devpod-vscode/container/config/`. That is a
real cost of decision 1 — the repository carries the contract so that
envbuilder's output is directly runnable — and it means these three files can
drift from the platform's. **If the devpod root's copies change, these must
change with them.** `make lint` at the Terraform level (`lint-workspace-contract`)
compares every seed's and example's copy against the devpod root's byte for
byte, so the drift is caught in the collection -- but not in a repository
already on the forge, which carries its own copy.
