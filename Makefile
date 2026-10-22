ENGINE      ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null)
MAILU_TAG   ?= 2024.06
IMAGE       ?= localhost/mailu-webmail-phphotfix
TAG         ?= $(MAILU_TAG)-php8.3.36
BUILD_ARGS  ?=

.PHONY: dev verify shell clean

## dev: build the image for the local architecture
dev:
	$(ENGINE) build -f Containerfile \
		--build-arg MAILU_TAG=$(MAILU_TAG) $(BUILD_ARGS) \
		-t $(IMAGE):$(TAG) .

## verify: show the PHP version and the hotfix settings in the image
verify:
	$(ENGINE) run --rm --entrypoint sh $(IMAGE):$(TAG) -c '\
		cat /version; php -v | head -1; \
		apk info -v 2>/dev/null | grep -E "^php83-(common|fpm)-"; \
		php -m | grep -E "^(snuffleupagus|apcu)$$"; \
		php -i | grep -E "^session.upload_progress.enabled"; \
		php-fpm83 -t'

## shell: open a shell in the image
shell:
	$(ENGINE) run --rm -it --entrypoint sh $(IMAGE):$(TAG)

clean:
	-$(ENGINE) rmi $(IMAGE):$(TAG)
