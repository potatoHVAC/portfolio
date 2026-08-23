# infra/bootstrap

Everything the other stacks need before they can exist: OpenTofu state, GitHub
OIDC identity, and the two image repositories.

Chunk 1 of the [walking skeleton spec](../../../docs/active/portfolio-walking-skeleton-spec.md)
in the parent `speerd` repository.

## What lives here and why

| | |
|---|---|
| **State bucket** | Versioned, SSE-S3, private, TLS-only. Holds state for *every* stack, not just this one. |
| **GitHub OIDC provider + three roles** | `portfolio-ci` (read-only), `portfolio-dev-deploy`, `portfolio-prod-deploy`. No long-lived AWS keys in GitHub. |
| **`dev/portfolio` and `prod/portfolio`** | ECR repositories. They are here rather than in `global` because **a container-image Lambda and an App Runner service cannot be created without an image already in the repository** — see the seed image chunk. |

`tofu apply` is **not** a CI action. Infrastructure is applied by a human with
the `steep` credentials; CI plans and deploys images. There is no apply role.

## First apply — one time, in this order

The chicken-and-egg: the backend needs a bucket that does not exist yet.

```sh
# 1. Run without the backend so state is local for one apply.
mv backend.tf backend.tf.pending
tofu init
tofu apply

# 2. Put the backend back and migrate the state into the bucket it just made.
mv backend.tf.pending backend.tf
tofu init -migrate-state

# 3. Confirm the migration, then delete the local copy.
tofu plan          # must be empty
rm -f terraform.tfstate terraform.tfstate.backup
```

`*.tfstate` and `*.tfstate.*` are gitignored at the repository root. **Never
commit the local state file** — between steps 1 and 3 it is the only copy.

If `speerd-portfolio-tfstate` is already taken globally, change
`var.state_bucket_name` **and** the literal in `backend.tf`; backend blocks
cannot take variables, which is also why the name deliberately does not embed
the account ID.

## Afterwards

Set in GitHub (Settings → Secrets and variables → Actions). **Done 2026-08-22.**

| Name | Kind | From |
|---|---|---|
| `AWS_REGION` | Variable | `us-west-2` |
| `AWS_CI_ROLE_ARN` | **Secret** | `tofu output -raw ci_role_arn` |
| `AWS_DEV_DEPLOY_ROLE_ARN` | **Secret** | `tofu output -raw dev_deploy_role_arn` |
| `AWS_PROD_DEPLOY_ROLE_ARN` | **Secret** | `tofu output -raw prod_deploy_role_arn` |
| `AWS_ACCOUNT_ID` | **Secret** | `aws sts get-caller-identity --query Account` |

**Secrets, not variables, and the reason matters.** These are ARNs rather than
credentials, so "variable" looks right — and would be, on a repository that
stays private. This one does not: it goes public as soon as the site is ready.

**GitHub Actions logs follow the repository's current visibility.** Every log
written while private becomes world-readable at the moment of the flip. Variable
values are printed in the clear; secret values are masked. So an ARN kept as a
variable quietly accumulates the account ID across every workflow run, and
publishes the lot retroactively.

`AWS_ACCOUNT_ID` holds no ARN and is referenced by nothing. It exists **only so
the runner masks that string**, including where it appears inside `tofu plan`
output. Register it explicitly as the first step of any job that prints AWS
output — implicit masking is not worth relying on:

```yaml
- run: echo "::add-mask::${{ secrets.AWS_ACCOUNT_ID }}"
```

Note this diverges from `BioSyft_Amara`, which uses `vars.AWS_CI_ROLE_ARN`.
That repository is private and staying private; this one is not.

Beware `gh variable list` — it prints values. `gh secret list` prints only names.

## Things that will bite

- **The `sub` conditions are exact strings.** A wildcard `sub` on a public
  repository is the standard critical misconfiguration. If a workflow cannot
  assume a role, fix the workflow's ref or environment — never widen the `sub`.
- **`prod/portfolio` has no lifecycle policy, on purpose.** It is the rollback
  set. Adding a count or age rule will eventually delete the image production is
  running.
- **`prod/portfolio` is IMMUTABLE.** Re-promoting a SHA already present fails
  the copy rather than overwriting. The promotion workflow checks first.
- **Two constructed ARNs** in `ci-identity.tf` name resources that do not exist
  yet (`portfolio-dev`, `portfolio-prod`). Rename either resource later and the
  deploy role silently stops working, with an access-denied that looks like a
  workflow bug.
