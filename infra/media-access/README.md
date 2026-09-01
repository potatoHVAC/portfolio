# Media access state

This OpenTofu root owns the delivery bucket's complete policy. It reads the
global, development, and production states and grants object reads only to the
two exact CloudFront distribution ARNs. Non-TLS bucket and object requests are
denied.

The global state owns the buckets but deliberately does not own the delivery
policy. Do not add a second policy owner elsewhere.

## Dependencies

Apply producing states before this consuming state:

1. `infra/envs/global`
2. `infra/envs/dev`
3. `infra/envs/prod`
4. `infra/media-access`

The backend key is `media-access/terraform.tfstate` in
`speerd-portfolio-tfstate`.

## Use

From this directory, with the repository-scoped `speerd` AWS profile active:

```sh
tofu init
tofu test
tofu plan
tofu apply
```

Applying the policy changes `/media/*` from the expected pre-policy `403` to
S3-backed delivery for existing objects. Removing or destroying it returns
media delivery to `403`; it does not delete a bucket or object.
