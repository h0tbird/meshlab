#------------------------------------------------------------------------------
# Buildtime
#------------------------------------------------------------------------------

FROM --platform=$BUILDPLATFORM alpine:edge AS build

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG VERSION=1.16.2

WORKDIR /tmp/

RUN apk --update add --virtual verify gpgme unzip \
 && PLATFORM=$(echo ${TARGETPLATFORM} | sed -e 's|/|_|g') \
 && wget https://releases.hashicorp.com/vault/${VERSION}/vault_${VERSION}_${PLATFORM}.zip \
 && wget https://releases.hashicorp.com/vault/${VERSION}/vault_${VERSION}_SHA256SUMS \
 && wget https://releases.hashicorp.com/vault/${VERSION}/vault_${VERSION}_SHA256SUMS.sig \
 && gpg --keyserver keyserver.ubuntu.com --recv-key 0x72D7468F \
 && gpg --verify /tmp/vault_${VERSION}_SHA256SUMS.sig \
 && cat vault_${VERSION}_SHA256SUMS | grep ${PLATFORM} | sha256sum -c \
 && unzip vault_${VERSION}_${PLATFORM}.zip

#------------------------------------------------------------------------------
# Runtime
#------------------------------------------------------------------------------

FROM alpine:edge

COPY --from=build /tmp/vault /usr/local/bin/vault

RUN apk --update add jq kubectl \
&& rm -rf /var/cache/apk/*

WORKDIR /
ENTRYPOINT ["/bin/sh"]
