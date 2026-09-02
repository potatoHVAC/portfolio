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
| `infra/modules/media-storage/` | Private original-media archive and derivative-delivery buckets |
| `infra/envs/global/` | Account-wide baseline, edge, DNS, and media storage |
| `bin/media`, `tools/media/` | Containerized media publisher and its tests |
| `config/media.json` | Committed public derivative manifest |

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

## Container

Build the deployable arm64 image, then smoke-test that exact artifact:

```sh
docker build --platform linux/arm64 -t portfolio:dev .
bin/smoke.sh portfolio:dev
```

The smoke test runs the container as shipped with a read-only root filesystem;
only `/tmp` is writable. The image serves on port 8080 as a non-root user.

Pushes to `main` publish the validated image to the development environment.

## Image metadata

Requires ExifTool, `file`, and `jq`. Check every committed image before it is
published; the same command runs as a standalone CI job.

```sh
tools/media/check-metadata.sh
tools/media/strip.sh path/to/image.jpg
```

The strip helper removes GPS, EXIF, XMP, and IPTC data while preserving an
embedded ICC colour profile. The gate covers `app/assets/images/` and image
files under `public/`.

## Media publishing

Keep owner source files under the Git-ignored `media-source/` tree. Images,
videos, and captions may share a directory, but primary image and video files
may not use the same extensionless relative path. Directory names and primary
basenames must be lowercase kebab case; that extensionless relative path becomes
the public asset ID.

Docker is the only host media-processing dependency. OpenTofu and the
repository-scoped `speerd` AWS profile are required for live publication.

```sh
bin/media check
bin/media ci
bin/media publish image media-source/rings/home/hero.jpg --alt "Portrait in studio"
bin/media publish image media-source/backgrounds/texture.jpg --decorative
bin/media publish video media-source/rings/home/demo.mp4 \
  --title "Ring controls" --description "A demonstration of the ring controls"
bin/media publish video media-source/rings/home/demo.mp4 \
  --title "Ring controls" --description "A selected demonstration" \
  --start 00:00:03.500 --end 00:00:08.000 \
  --captions en-US:media-source/rings/home/demo.en-us.vtt
bin/media verify-manifest
bin/media verify-manifest --remote https://speerd.com
bin/media hydrate
```

`bin/media ci` is credential-free. It runs the pinned ESLint and binary-backed
test suite, validates the committed manifest, scans committed public media for
metadata, and rejects tracked source or hydrated files. Pushes to `main` also
verify every manifest object through the public CloudFront origin with HEAD and
video Range requests after the development deployment.

Publication handles one selected asset at a time. It archives the source bytes,
publishes metadata-free content-addressed derivatives, and updates
`config/media.json` only after object readback succeeds. Reusing an asset ID
with changed bytes or accessibility content requires `--replace`. The command
is additive: it does not scan a directory for publication or delete remote
objects when a local file disappears. Source files and hydrated files under
`public/media/` must never be committed.

Video publication re-encodes H.264/AAC MP4 derivatives and a JPEG poster. Supply
both `--start` and `--end` to publish a clip, or neither to publish the full
video. Caption files use WebVTT and the primary stem plus a lowercase BCP 47
language suffix, such as `demo.en-us.vtt`; repeat `--captions language:path` for
additional tracks. Use `--caption-label language:label` to override the visible
label. The complete original video and caption bytes are archived.

Render published entries from Rails with the manifest-backed helpers. Image
callers supply the responsive `sizes` contract; development fetches only the
manifest-referenced public derivatives.

```erb
<%= portfolio_picture "rings/home/hero", sizes: "(min-width: 60rem) 60rem, 100vw" %>
<%= portfolio_video "videos/studio-tour", class: "studio-tour" %>
```

Run `bin/media hydrate` after a manifest change to reproduce the root-relative
`public/media/` hierarchy locally. The home page renders both published
validation assets through these helpers.

## Configuration

The app and its container entrypoint read these environment variables:

| Variable | Where it comes from |
|---|---|
| `SECRET_KEY_BASE` | Optional direct value; the smoke test supplies one |
| `SECRET_KEY_BASE_PARAMETER` | SSM path; defaults to `/portfolio/secret_key_base` |
| `RAILS_LOG_LEVEL` | Optional; defaults to `info` in production |

There is **no `config/credentials.yml.enc` and no `config/master.key`** — they
were deleted deliberately. `SECRET_KEY_BASE` comes from SSM, and a second secret
system distributed out of band would be one more thing to lose. Asset
precompilation uses `SECRET_KEY_BASE_DUMMY=1`, which needs no real secret.

At container boot, the entrypoint uses `SECRET_KEY_BASE` when it is already set;
otherwise it reads `SECRET_KEY_BASE_PARAMETER` from SSM in `us-west-2` with the
runtime's AWS identity. It does not write the value to disk or logs.

Without `SECRET_KEY_BASE`, production returns 500 on **every** path including
`/up` — a missing secret fails the health check rather than serving a broken
page behind a green one.
