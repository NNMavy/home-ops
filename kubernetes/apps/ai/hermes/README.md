# Hermes

Hermes exposes two interfaces from the same persistent profile:

- Native Webapp: `https://hermes.codewalker.dev` (gateway port 9120).
- Hermes Dashboard: `https://hermes-dash.codewalker.dev` (port 9119).

Both are routed through `envoy-internal`, so they are reachable only on the LAN.

The single application container runs the gateway and Dashboard under the image's
s6 supervisor. `gateway run` starts the gateway, which serves the Webapp;
`HERMES_DASHBOARD=true` enables the separate Dashboard process on port 9119.

Connect Hermes Desktop to `https://hermes.codewalker.dev` and sign in through authentik.
This endpoint uses the gateway's live session authority. The standalone Dashboard
retains maintenance operations that require exclusive database access and can be
refused while the gateway owns the profile, even when both processes share a container.

## Image and authentication

The backend and Dashboard run the released `docker.io/nousresearch/hermes-agent`
image pinned by tag and digest in `app/helmrelease.yaml`; Renovate proposes updates.
The image includes the prebuilt Webapp and confidential OIDC support.

Both interfaces sign in through authentik's `hermes` application
(`https://authentik.codewalker.dev/application/o/hermes/`), sharing one
confidential client and using `/auth/callback` on their respective hostnames. The
client ID and secret come from the 1Password `hermes` item (`oauth_client_id`,
`oauth_client_secret`) through the `hermes` ExternalSecret. Who may sign in is
decided by the bindings on that authentik application, which live in authentik,
not in this repository. Every admitted account has full agent access.

## Configuration ownership

`app/resources/config.yaml` is a read-only managed overlay mounted at
`/etc/hermes/config.yaml` (Hermes' supported path). It pins the Webapp and
Dashboard addresses, authentik OIDC, the gateway topology, secret redaction, the
local terminal backend (passing `SEARXNG_URL` through to terminal sessions), and
disables shared telemetry. Managed values take precedence over each profile's
settings.

Profile configuration, `.env`, and `SOUL.md` live on the PVC. The deployment
does not seed or rewrite profile files at startup. Hermes' per-profile command
secret source reads the Agent Gateway key from a read-only Kubernetes Secret mount and
supplies the SearXNG URL. The pod exposes the existing shared mise install and
shims through `PATH` and reuses the existing workspace on the PVC.

Hermes resolves secret sources and external skill directories from each profile's
raw `config.yaml`, bypassing the machine-level overlay. `hermes doctor` likewise
validates `model.provider` against the profile's raw `providers` section only. These settings must be
owned exclusively by the profile: declaring them in `/etc/hermes/config.yaml`
causes every Dashboard config save to strip them from the profile, even though
their runtime readers cannot inherit the managed values. Keep `secrets.command`,
`skills.external_dirs` and `providers` out of the overlay.

For each profile that needs Agent Gateway credentials and the shared toolkit, merge the
following into `/opt/data/profiles/<name>/config.yaml` (or `/opt/data/config.yaml`
for the default profile). Preserve sibling settings such as `skills.disabled`,
other secret sources, and all unrelated preferences. This contains only a helper
declaration, never the resolved credential:

```yaml
model:
  base_url: http://agentgateway.ai.svc.cluster.local:8080/v1
  provider: agentgateway

providers:
  agentgateway:
    api: http://agentgateway.ai.svc.cluster.local:8080/v1
    discover_models: true
    key_env: AGENTGATEWAY_API_KEY
    name: Agent Gateway

secrets:
  command:
    enabled: true
    command: |
      set -eu
      printf 'AGENTGATEWAY_API_KEY='
      /bin/cat /mnt/secrets/agentgateway/key
      printf '\nSEARXNG_URL=http://searxng-app.selfhosted.svc.cluster.local:8080\n'
    helper_timeout_seconds: 3
    override_existing: true

skills:
  external_dirs:
    - /opt/data/shared/skills
```

After changing a profile, restart the gateway so it rebuilds profile credential
scopes and MCP connections. To confirm a profile kept these settings, save an
unrelated preference in the Dashboard and check they are still in its file. Never
print the helper output when checking credential availability.

## Network

The HelmRelease's `networkpolicies.hermes` (a CiliumNetworkPolicy) confines the pod.
Ingress is allowed only from `envoy-internal` on 9119 and 9120. Egress is allowed only to:

| Destination | Port | Purpose |
| --- | --- | --- |
| Cluster DNS (`kube-system/kube-dns`) | 53 | Name resolution |
| `ai/agentgateway` | 8080, 8081 | Models (LLM) and MCP servers |
| `selfhosted/searxng` | 8080 | Web search |
| `envoy-external`, SNI `authentik.codewalker.dev` | 10443 | OIDC sign-in (envoy's 443 listener; policy sees the container port) |
| `holocron` CiliumCIDRGroup, SNI `git.codewalker.dev` | 443 | Forgejo, which runs on holocron outside the cluster |

Hermes therefore has no general internet access: web page fetches, package
installs and new mise tools fail unless their destination is added here. The pod's
`egress.policy.home.arpa/internet` label has no policy behind it in this
repository and grants nothing. The authentik rule depends on split-horizon DNS:
internally `authentik.codewalker.dev` resolves to envoy-external's LoadBalancer
IP, which Cilium sends to the envoy-external pods; the public answer (the VPS
relay) would not match.

## Shared forge toolkit and workspace

The Forge Toolkit is already installed on the persistent PVC under
`/opt/data/shared/`. Pod restarts reuse the existing files; profiles load
`/opt/data/shared/skills` through their own `skills.external_dirs` setting as
described above. Configure this explicitly for each new profile that needs it.

Repository identifiers always use `HOST/OWNER/REPO`. The `forge-repos` skill
guides discovery; `forge-git repo path` resolves the canonical path and
`forge-git repo ensure` reuses a matching checkout or clones a missing one under
`/opt/data/workspace/repos/<host>/<owner>/<repo>`. Existing remotes are checked;
the helper does not reset or update an existing checkout.

`hermes-forgejo` is the source of the read-only
`/mnt/secrets/forges/forgejo/git.codewalker.dev` credential (1Password `forgejo`
item, `lab_assistant_token`). `forge-auth` selects a
CLI by both provider and hostname, while Git's shared global config uses
`git-credential-forge` and disables synthesized identities. `forge-git` resolves
commit identity from the authenticated account API or an operator-supplied
`/opt/data/shared/forge-identities.json`. That optional file is deliberately
not created or populated by GitOps. Never put credentials in it or in GitOps.

To add another forge, create an ExternalSecret only after its credential exists,
mount the Secret read-only at
`/mnt/secrets/forges/<provider>` with its key named for the forge hostname, and
add the hostname/provider pair to the persistent host mapping. Add only the
required egress for that forge to the network policy, preserving the existing
Forgejo rule. Review the provider's documented CLI and API endpoints before
enabling it. Do not put tokens in the host mapping or CLI configuration. The
existing mise tools and Forge Toolkit files are operator-maintained on the PVC
and are not refreshed by pod startup. Git and Python remain available from the
Hermes image and mise shims on `PATH`.

## Upgrades

The `config-migrate` init container runs the image's configuration migration
before s6 starts. The image's own boot hook calls it through `s6-setuidgid`,
which fails as non-root. The PVC is snapshotted by kopiur (`components/kopiur/backup`).
Before a major image upgrade, confirm a recent usable snapshot: an upgrade can
migrate configuration or session databases.

After an upgrade, check that:

1. `config-migrate` completes and the gateway heartbeat stays fresh (the probes
   require `/opt/data/cron/ticker_heartbeat` to be under five minutes old).
2. The Webapp and Dashboard require sign-in, a permitted authentik account
   completes each flow, and an account not admitted by the `hermes`
   application cannot obtain access.
3. The Webapp lists the intended profiles and can create a chat, stream a reply,
   and continue it after a browser reload.

Reverting the image through Git does not undo persistent database migrations. If
the older image cannot read migrated state, restore a verified PVC snapshot with
an explicitly approved recovery procedure; do not delete or overwrite the PVC as
a routine rollback step.
