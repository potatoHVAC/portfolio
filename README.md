# speerdrings

Source, content planning, and assets for the **SPEERD** portfolio website.

The site showcases three areas of work:

- Cosplay
- Metalwork
- LED artwork

Website: [www.speerd.com](https://www.speerd.com)

## Repository layout

| Path | What |
|---|---|
| `app/`, `config/`, `test/` | The Rails application — one page, no database |
| `infra/bootstrap/` | State bucket, GitHub OIDC identity, ECR repositories |
| `infra/modules/baseline/` | CloudTrail, budget, and the alert topic |
| `infra/envs/global/` | Account-wide stack; instantiates `baseline` |

Infrastructure is [OpenTofu](https://opentofu.org). See
`infra/bootstrap/README.md` for the one-time bootstrap sequence.

## Running locally

Requires the Ruby in `.ruby-version` (3.4.4).

```sh
bundle install
bin/rails test      # green is the gate for every commit
bin/rails server    # http://localhost:3000
```

`/up` is the health endpoint; it returns 200 when the app boots cleanly.

## Configuration

The app reads two environment variables and has no other configuration:

| Variable | Where it comes from |
|---|---|
| `SECRET_KEY_BASE` | SSM Parameter Store (`/portfolio/*`) at deploy time |
| `RAILS_LOG_LEVEL` | Optional; defaults to `info` in production |

There is **no `config/credentials.yml.enc` and no `config/master.key`** — they
were deleted deliberately. `SECRET_KEY_BASE` comes from SSM, and a second secret
system distributed out of band would be one more thing to lose. Asset
precompilation uses `SECRET_KEY_BASE_DUMMY=1`, which needs no real secret.

Without `SECRET_KEY_BASE`, production returns 500 on **every** path including
`/up` — a missing secret fails the health check rather than serving a broken
page behind a green one.
