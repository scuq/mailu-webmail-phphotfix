# mailu-webmail-phphotfix

Mailu webmail (`ghcr.io/mailu/webmail:2024.06`) with PHP 8.3.36.

PHP 8.3.36 fixes CVE-2026-109618 and CVE-2026-109619 (PHP2Shell). The
upstream image `2024.06.65` contains PHP 8.3.15 from Alpine 3.20.

## How it works

1. The `builder` stage builds the Alpine edge `php83` APKBUILD (8.3.36-r0) on
   Alpine 3.20. The aports commit is pinned in `APORTS_COMMIT`.
2. The final stage upgrades all `php83*` packages in the Mailu image from that
   local repository.
3. The final stage sets `session.upload_progress.enabled = 0` in `conf.d` and
   in the FPM pool.
4. The build fails if PHP is older than 8.3.36, if `snuffleupagus` or `apcu`
   does not load, or if `php-fpm83 -t` fails.

## Local build

```sh
make dev        # build localhost/mailu-webmail-phphotfix:2024.06-php8.3.36
make verify     # show PHP version and hotfix settings
make dev MAILU_TAG=2024.06.65
```

`ENGINE` defaults to podman, then docker.

## CI build

`.github/workflows/build.yml` builds `linux/amd64` and `linux/arm64` on native
runners and pushes to `ghcr.io/<owner>/<repo>` with these tags:

- `2024.06-php8.3.36`
- `2024.06`
- `sha-<commit>`

Pull requests build only. A weekly run picks up new upstream Mailu images.

## Use in Mailu

In `docker-compose.yml`, replace the webmail image:

```yaml
webmail:
  image: ghcr.io/<owner>/mailu-webmail-phphotfix:2024.06-php8.3.36
```

Remove this override when Mailu releases an image with PHP 8.3.36 or later.
