## setup dependencies
FROM debian:stable-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG URL=https://nlnetlabs.nl/downloads/unbound/unbound-latest.tar.gz

RUN <<EOF
set -eux

apt-get update
apt-get upgrade --yes
apt-get install --no-install-recommends --no-install-suggests --yes \
  bison \
  build-essential \
  flex \
  gcc \
  git \
  libssl-dev \
  libexpat1-dev \
  make

EOF

ADD $URL /

RUN <<EOF
set -eux

cd /tmp
# wget https://nlnetlabs.nl/downloads/unbound/unbound-latest.tar.gz
mkdir --parents /unbound
cd /unbound
tar xzf /unbound-latest.tar.gz -C /unbound --strip-components=1
./configure --disable-shared --enable-static --enable-static-exe --enable-fully-static
make
make install
EOF

## setup unbound and create a functional default configuration file
RUN <<EOF
set -eux

apt-get install --no-install-recommends --no-install-suggests --yes \
  dns-root-data
mv /usr/local/etc/unbound/unbound.conf /usr/local/etc/unbound/example.conf

cat <<-EOR >> /usr/local/etc/unbound/unbound.conf
# unbound.conf(5) config file for unbound(8).
server:
  directory: "/usr/local/etc/unbound"
  username: ""
  # make sure unbound can access entropy from inside the chroot.
  # e.g. on linux the use these commands (on BSD, devfs(8) is used):
  #      mount --bind -n /dev/urandom /etc/unbound/dev/urandom
  # and  mount --bind -n /dev/log /etc/unbound/dev/log
  chroot: ""
  # logfile: "/usr/local/etc/unbound/unbound.log"  #uncomment to use logfile.
  # pidfile: "/usr/local/etc/unbound/unbound.pid"
  # verbosity: 1      # uncomment and increase to get more logging.
  # listen on all interfaces, answer queries from the local subnet.
  root-hints: /root.hints
  interface: 0.0.0.0
  interface: ::0
  access-control: 10.0.0.0/8 allow
  access-control: 2001:DB8::/64 allow
EOR

unbound-anchor -a /usr/local/etc/unbound/root.key || true
unbound-control-setup

EOF


## final image
FROM scratch AS release

ARG IMAGE_DATE
ARG IMAGE_URL
ARG IMAGE_VERSION
LABEL org.opencontainers.image.created="$IMAGE_DATE" \
      org.opencontainers.image.description="Unbound is a validating, recursive, caching DNS resolver. It is designed to be fast and lean and incorporates modern features based on open standards." \
      org.opencontainers.image.title="unbound" \
      org.opencontainers.image.url="$IMAGE_URL" \
      org.opencontainers.image.version="$IMAGE_VERSION"

COPY --from=builder --chmod=555 /usr/local/sbin/unbound /usr/local/sbin/unbound
COPY --from=builder --chmod=555 /usr/local/sbin/unbound-checkconf /usr/local/sbin/unbound-checkconf
COPY --from=builder --chmod=555 /usr/local/sbin/unbound-control /usr/local/sbin/unbound-control
COPY --from=builder --chmod=555 /usr/local/sbin/unbound-host /usr/local/sbin/unbound-host
COPY --from=builder --chmod=555 /usr/local/sbin/unbound-anchor /usr/local/sbin/unbound-anchor
COPY --from=builder --chmod=444 /usr/local/etc/unbound /usr/local/etc/unbound
COPY --from=builder --chmod=444 /usr/share/dns/root.hints /usr/share/dns/root.hints
COPY --from=builder --chmod=444 /usr/share/dns/root.hints  /usr/local/etc/unbound/root.hints

WORKDIR /usr/local/etc/unbound/

USER 10000:10000

ENTRYPOINT [ "/usr/local/sbin/unbound" ]
CMD [ "-ddpv" ]

HEALTHCHECK \
  --interval=30s \
  --timeout=30s \
  --start-period=30s \
  --retries=3 \
  CMD [ "/usr/local/sbin/unbound-host", "-ddv", "www.google.com" ]
