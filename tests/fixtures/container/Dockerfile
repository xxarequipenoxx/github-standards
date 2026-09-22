# Fixture for container.yml: minimal image that reads a build secret through a BuildKit
# secret mount (the build-secrets input) and runs as a non-root user.
FROM docker.io/library/alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8

# The secret is only readable during this RUN step; nothing of it lands in a layer.
RUN --mount=type=secret,id=fixture_token test -s /run/secrets/fixture_token \
    && echo "fixture build $(date -u +%Y-%m-%dT%H:%M:%SZ)" > /etc/fixture-release

USER 65532:65532
CMD ["cat", "/etc/fixture-release"]
