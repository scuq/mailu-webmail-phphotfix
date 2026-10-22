# Mailu webmail with a rebuilt PHP 8.3 (PHP2Shell hotfix).
#
# The upstream image (ghcr.io/mailu/webmail:2024.06.x) is based on Alpine 3.20,
# which ships php83 8.3.15. CVE-2026-109618 and CVE-2026-109619 are fixed in
# PHP 8.3.36. Alpine edge has php83 8.3.36-r0, but edge binaries are not ABI
# compatible with Alpine 3.20. This file builds the edge php83 APKBUILD on
# Alpine 3.20 and upgrades the php83 packages in the Mailu image from that
# local repository.

ARG MAILU_IMAGE=ghcr.io/mailu/webmail
ARG MAILU_TAG=2024.06
ARG ALPINE_VERSION=3.20

# ---------------------------------------------------------------------------
# Stage 1: build php83 apk packages for the same Alpine release as the base.
# ---------------------------------------------------------------------------
FROM docker.io/library/alpine:${ALPINE_VERSION} AS builder

# aports commit that contains community/php83 at 8.3.36-r0.
ARG APORTS_REPO=https://github.com/alpinelinux/aports.git
ARG APORTS_COMMIT=760c400bf8d9f3809a52d07443c5363864736887
ARG PHP_EXPECTED_VERSION=8.3.36
# Alpine 3.20 has clang 15-18. Edge uses clang 21.
ARG CLANG_VERSION=18
# Set to 1 to run the PHP test suite (adds a lot of build time).
ARG PHP_RUN_TESTS=0

RUN apk add --no-cache alpine-sdk sudo git \
 && adduser -D builder \
 && addgroup builder abuild \
 && echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder

USER builder
WORKDIR /home/builder
# abuild-keygen names the signing key after this address.
ENV PACKAGER="phphotfix <phphotfix@localhost>"

RUN git init -q aports \
 && cd aports \
 && git remote add origin "${APORTS_REPO}" \
 && git sparse-checkout set community/php83 \
 && git fetch -q --depth 1 --filter=blob:none origin "${APORTS_COMMIT}" \
 && git checkout -q FETCH_HEAD

WORKDIR /home/builder/aports/community/php83

RUN set -eu; \
    grep -qx "pkgver=${PHP_EXPECTED_VERSION}" APKBUILD \
      || { echo "APKBUILD is not php ${PHP_EXPECTED_VERSION}" >&2; exit 1; }; \
    sed -i "s/^_clang_ver=.*/_clang_ver=${CLANG_VERSION}/" APKBUILD; \
    # php83 is the default PHP on Alpine 3.20 and owns /usr/bin/php there.
    sed -i 's/^_default_php=.*/_default_php="yes"/' APKBUILD; \
    if [ "${PHP_RUN_TESTS}" != "1" ]; then \
      echo 'options="$options !check"' >> APKBUILD; \
    fi; \
    abuild-keygen -a -i -n; \
    sudo apk update; \
    abuild -r; \
    mkdir -p /home/builder/keys; \
    cp /home/builder/.abuild/*.rsa.pub /home/builder/keys/

# ---------------------------------------------------------------------------
# Stage 2: upgrade php83 in the Mailu webmail image.
# ---------------------------------------------------------------------------
FROM ${MAILU_IMAGE}:${MAILU_TAG}

ARG PHP_EXPECTED_VERSION=8.3.36

COPY --from=builder /home/builder/packages/community /tmp/php-repo
COPY --from=builder /home/builder/keys /tmp/php-repo-keys

RUN set -eu; \
    pkgs="$(apk info | grep -E '^php83(-|$)' | grep -v '^php83-pecl-')"; \
    cp -- /tmp/php-repo-keys/*.rsa.pub /etc/apk/keys/; \
    find /etc/php83 | sort > /tmp/php-etc.before; \
    apk upgrade --no-cache --repository /tmp/php-repo $pkgs; \
    # Mailu removes stock config such as php-fpm.d/www.conf. Do not let the
    # upgrade bring it back.
    find /etc/php83 | sort | comm -13 /tmp/php-etc.before - \
      | xargs -r rm -rfv --; \
    rm -f /tmp/php-etc.before; \
    for k in /tmp/php-repo-keys/*.rsa.pub; do \
      rm -f -- "/etc/apk/keys/${k##*/}"; \
    done; \
    rm -rf /tmp/php-repo /tmp/php-repo-keys

# Defense in depth for CVE-2026-109619. Roundcube does not use upload progress.
# start.py renders /etc/php83/php.ini at runtime, so do not edit php.ini.
RUN set -eu; \
    printf '%s\n' \
      '; phphotfix: CVE-2026-109619 mitigation' \
      'session.upload_progress.enabled = 0' \
      > /etc/php83/conf.d/99-phphotfix.ini; \
    printf '%s\n' \
      '' \
      '; phphotfix: CVE-2026-109619 mitigation' \
      'php_admin_flag[session.upload_progress.enabled] = off' \
      >> /etc/php83/php-fpm.d/php-webmail.conf

# Fail the build if the runtime is not fixed or does not start.
RUN set -eu; \
    V="${PHP_EXPECTED_VERSION}" \
      php -r 'exit(version_compare(PHP_VERSION, getenv("V"), ">=") ? 0 : 1);'; \
    php -v; \
    php -m | grep -qx snuffleupagus; \
    php -m | grep -qx apcu; \
    test "$(php -r 'echo (int) ini_get("session.upload_progress.enabled");')" = 0; \
    test "$(ls /etc/php83/php-fpm.d)" = php-webmail.conf; \
    php-fpm83 -t

LABEL org.opencontainers.image.title="mailu-webmail-phphotfix" \
      org.opencontainers.image.description="Mailu webmail with PHP ${PHP_EXPECTED_VERSION} (CVE-2026-109618, CVE-2026-109619)"
