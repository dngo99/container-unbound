ARG LIBMNL_VERSION=1.0.5
# ARG NGTCP2_VERSION=1.13.0
ARG OPENSSL_VERSION=3.5.1
ARG UNBOUND_VERSION=1.23.0

ARG DIR_BUILD=/build
ARG DIR_CONTAINER=/container
ARG DIR_INSTALL=/opt


############################## STAGE 1 ##############################
FROM --platform=${BUILDPLATFORM} docker.io/library/debian:stable-slim AS crossbuild-host
ARG DIR_BUILD
ARG DIR_INSTALL

########## DOWNLOADS ##########
ARG LIBMNL_VERSION
ADD "https://www.netfilter.org/projects/libmnl/files/libmnl-${LIBMNL_VERSION}.tar.bz2" \
  "${DIR_BUILD}/libmnl.tar.bz2"
# ARG NGTCP2_VERSION
# ADD "https://github.com/ngtcp2/ngtcp2/releases/download/v${NGTCP2_VERSION}/ngtcp2-${NGTCP2_VERSION}.tar.gz" \
#   "${DIR_BUILD}/ngtcp2.tar.gz"
ARG OPENSSL_VERSION
ADD "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
  "${DIR_BUILD}/openssl.tar.gz"
ARG UNBOUND_VERSION
ADD "https://github.com/NLnetLabs/unbound/archive/refs/tags/release-${UNBOUND_VERSION}.tar.gz" \
  "${DIR_BUILD}/unbound.tar.gz"
########## DOWNLOADS ##########

ARG BUILDPLATFORM
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
set -eux

BUILD_ARCH=""
case "${BUILDPLATFORM}" in
  "linux/arm/v7") BUILD_ARCH="armhf" ;;
  "linux/arm64/v8") BUILD_ARCH="arm64" ;;
  "linux/amd64") BUILD_ARCH="amd64" ;;
  *) exit 1 ;;
esac

apt update
apt install --no-install-recommends --no-install-suggests --yes \
  ca-certificates:${BUILD_ARCH} \
  cmake:${BUILD_ARCH} \
  build-essential:${BUILD_ARCH} \
  make:${BUILD_ARCH} \
  pkg-config:${BUILD_ARCH}
apt install --no-install-recommends --no-install-suggests --yes \
  bison:${BUILD_ARCH} \
  build-essential:${BUILD_ARCH} \
  flex:${BUILD_ARCH} \
  gcc:${BUILD_ARCH} \
  git:${BUILD_ARCH}
apt install --no-install-recommends --no-install-suggests --yes \
  automake:${BUILD_ARCH} \
  autoconf:${BUILD_ARCH} \
  libtool:${BUILD_ARCH} \
  pkg-config:${BUILD_ARCH}

apt install --no-install-recommends --no-install-suggests --yes \
  lbzip2:${BUILD_ARCH}
tar --directory="${DIR_BUILD}" --extract --one-top-level --strip-components=1 --file="${DIR_BUILD}/libmnl.tar.bz2"
# tar --directory="${DIR_BUILD}" --extract --one-top-level --strip-components=1 --file="${DIR_BUILD}/ngtcp2.tar.gz"
tar --directory="${DIR_BUILD}" --extract --one-top-level --strip-components=1 --file="${DIR_BUILD}/openssl.tar.gz"
tar --directory="${DIR_BUILD}" --extract --one-top-level --strip-components=1 --file="${DIR_BUILD}/unbound.tar.gz"
apt remove --yes \
  lbzip2:${BUILD_ARCH}

apt remove --yes \
  libevent-dev:${BUILD_ARCH} \
  libexpat1-dev:${BUILD_ARCH} \
  libhiredis-dev:${BUILD_ARCH} \
  libnghttp2-dev:${BUILD_ARCH} \
  libngtcp2-dev:${BUILD_ARCH} \
  libmnl-dev:${BUILD_ARCH} \
  libprotobuf-c-dev:${BUILD_ARCH} \
  protobuf-c-compiler:${BUILD_ARCH} \
  libsodium-dev:${BUILD_ARCH} \
  libssl-dev:${BUILD_ARCH}

apt autoremove --yes 
apt autoclean --yes
apt clean --yes

EOF

########## COMPILE FLAGS ##########
## https://stackoverflow.com/questions/29054273/libtool-is-discarding-static-flag/29055118#29055118
## --static 
ARG STATIC="-static-libstdc++ -static-libgcc -static --static"
## https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html
## CFLAG: -fstrict-flex-arrays=3 requires GCC 13.0
## CFLAG: -fhardened require GCC 14.0
ARG CFLAGS="-O2 -pipe -fPIE -pie"
ARG CFLAGS="${CFLAGS} -fstack-clash-protection -fstack-protector-strong"
ARG CFLAGS="${CFLAGS} -fno-delete-null-pointer-checks -fno-strict-overflow -fno-strict-aliasing -ftrivial-auto-var-init=zero -fexceptions"
ARG CXXFLAGS="${CFLAGS}"
ARG CPPFLAGS="-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS -I${DIR_INSTALL}/include"
ARG LDFLAGS="-L${DIR_INSTALL}/lib -L${DIR_INSTALL}/lib64"
ARG LDFLAGS="${LDFLAGS} -fPIE -pie -s -pthread -Wl,-O1 -Wl,-z,nodlopen -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -Wl,--no-copy-dt-needed-entries"
ARG PKG_CONFIG_PATH="${DIR_INSTALL}/lib/pkgconfig:${DIR_INSTALL}/lib64/pkgconfig"
########## COMPILE FLAGS ##########


#################### CACHE INVALIDATION ####################

ARG TARGETARCH
ARG TARGETPLATFORM
RUN <<EOF
set -eux

BUILD_HOST=""
case "${BUILDPLATFORM}" in
  "linux/arm/v7")
    BUILD_ARCH="armhf"
    BUILD_HOST="arm-linux-gnueabihf"
    ;;
  "linux/arm64/v8")
    BUILD_ARCH="arm64"
    BUILD_HOST="aarch64-linux-gnu"
    ;;
  "linux/amd64")
    BUILD_ARCH="amd64"
    BUILD_HOST="x86_64-linux-gnu"
    ;;
  *) exit 1 ;;
esac

case "${TARGETPLATFORM}" in
  "linux/arm/v7")
    TARGET_ARCH="armhf"
    TARGET_DEBIAN="arm-linux-gnueabihf"
    TARGET_HOST="arm-linux-gnueabihf"
    TARGET_OPENSSL="linux-armv4"
    TARGET_ARCH_CFLAGS="-march=armv7-a+fp -mfloat-abi=hard"
    ;;
  "linux/arm64/v8")
    TARGET_ARCH="arm64"
    TARGET_DEBIAN="aarch64-linux-gnu"
    TARGET_HOST="aarch64-linux-gnu"
    TARGET_OPENSSL="linux-aarch64"
    TARGET_ARCH_CFLAGS="-march=armv8-a -mbranch-protection=standard"
    ;;
  "linux/amd64")
    TARGET_ARCH="amd64"
    TARGET_DEBIAN="x86-64-linux-gnu"
    TARGET_HOST="x86_64-linux-gnu"
    TARGET_OPENSSL="linux-x86_64"
    TARGET_ARCH_CFLAGS="-march=x86-64-v3 -fcf-protection=full"
    ;;
  *) exit 1 ;;
esac

apt install --no-install-recommends --no-install-suggests --yes \
  binutils-${TARGET_DEBIAN}:${BUILD_ARCH} \
  crossbuild-essential-${TARGET_ARCH}:${BUILD_ARCH} \
  gcc-${TARGET_DEBIAN}:${BUILD_ARCH} \
  g++-${TARGET_DEBIAN}:${BUILD_ARCH} \
  linux-libc-dev-${TARGET_ARCH}-cross:${BUILD_ARCH}

dpkg --add-architecture ${TARGET_ARCH}
apt update
apt install --yes \
  libevent-dev:${TARGET_ARCH} \
  libexpat1-dev:${TARGET_ARCH} \
  libhiredis-dev:${TARGET_ARCH} \
  libnghttp2-dev:${TARGET_ARCH} \
  libprotobuf-c-dev:${TARGET_ARCH} \
  protobuf-c-compiler:${TARGET_ARCH} \
  libsodium-dev:${TARGET_ARCH}
apt remove --yes \
  libmnl-dev:${TARGET_ARCH} \
  libngtcp2-dev:${TARGET_ARCH} \
  libssl-dev:${TARGET_ARCH}


export CFLAGS="${TARGET_ARCH_CFLAGS} ${CFLAGS}"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="${STATIC} -L/usr/lib/${TARGET_HOST} -L/lib/${TARGET_HOST} -L/usr/${TARGET_HOST}/lib ${LDFLAGS}"
export LD_LIBRARY_PATH="/usr/lib/${TARGET_HOST}:/lib/${TARGET_HOST}:/usr/${TARGET_HOST}/lib"
export PKG_CONFIG_PATH="/usr/lib/${TARGET_HOST}/pkgconfig:/lib/${TARGET_HOST}/pkgconfig:/usr/${TARGET_HOST}/lib/pkgconfig:${PKG_CONFIG_PATH}"
# export CC="/usr/bin/${TARGET_HOST}-gcc"
# export CXX="/usr/bin/${TARGET_HOST}-g++"
# export AR="/usr/bin/${TARGET_HOST}-gcc-ar"

#################### OPENSSL ####################
cd "${DIR_BUILD}/openssl"
./Configure \
  ${TARGET_OPENSSL} \
  --prefix="${DIR_INSTALL}" \
  --cross-compile-prefix=${TARGET_HOST}- \
  --release \
  -static \
  no-apps \
  no-comp \
  no-docs \
  no-shared \
  enable-tfo

make -j$(nproc)
make install_sw
make install_ssldirs
#################### OPENSSL ####################

#################### LIBMNL ####################
## Debian does not package a static library libmnl.a
cd "${DIR_BUILD}/libmnl"
./configure \
  --prefix="${DIR_INSTALL}" \
  --build="${BUILD_HOST}" \
  --host="${TARGET_HOST}" \
  --enable-static \
  --disable-shared \
  --with-gnu-ld

make -j$(nproc)
make install
#################### LIBMNL ####################

# #################### NGTCP2 ####################
# cd "${DIR_BUILD}/ngtcp2"
# ./configure \
#   --build=${BUILD_HOST} \
#   --disable-shared \
#   --enable-lib-only \
#   --enable-static \
#   --host=${TARGET_HOST} \
#   --target=${TARGET_HOST} \
#   --prefix="${DIR_INSTALL}" \
#   --with-openssl

# make
# make install
# #################### NGTCP2 ####################

## https://github.com/NLnetLabs/unbound/issues/1013
## unaligned tcache chunk detected
## Fixed by building with --without-pthreads
#################### UNBOUND ####################
## https://github.com/NLnetLabs/unbound/blob/master/configure
cd "${DIR_BUILD}/unbound"
${DIR_BUILD}/unbound/configure \
  --prefix="/usr/local" \
  --build="${BUILD_HOST}" \
  --host="${TARGET_HOST}" \
  --disable-shared \
  --enable-static \
  --enable-relro-now \
  --enable-subnet \
  --enable-tfo-client \
  --enable-tfo-server \
  --enable-static-exe \
  --enable-fully-static \
  --enable-dnstap \
  --enable-dnscrypt \
  --enable-cachedb \
  --enable-ipsecmod \
  --enable-ipset \
  --with-username="" \
  --without-pthreads \
  --with-ssl="${DIR_INSTALL}" \
  --with-libevent \
  --with-libexpat="/usr" \
  --with-libhiredis \
  --with-libnghttp2="/usr" \
  --without-libngtcp2 \
  --with-protobuf-c="/usr/lib/${TARGET_HOST}" \
  --with-libsodium="/usr/lib/${TARGET_HOST}" \
  --with-libmnl="${DIR_INSTALL}"

make -j$(nproc)
make install
#################### UNBOUND ####################
EOF
############################## STAGE 1 ##############################


############################## STAGE 2 ##############################
FROM --platform=${TARGETPLATFORM} docker.io/library/debian:stable-slim AS build-generic

## Unbound Binaries and Scripts
COPY --from=crossbuild-host \
  /usr/local/sbin \
  /usr/local/sbin
## Unbound Configuration Files
COPY --from=crossbuild-host \
  /usr/local/etc/unbound \
  /usr/local/etc/unbound

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETPLATFORM
RUN <<EOF
set -eux

case "${TARGETPLATFORM}" in
  "linux/arm/v7") TARGET_ARCH="armhf" ;;
  "linux/arm64/v8") TARGET_ARCH="arm64" ;;
  "linux/amd64") TARGET_ARCH="amd64" ;;
  *) exit 1 ;;
esac

apt update
apt install --no-install-recommends --no-install-suggests --yes \
  binutils:${TARGET_ARCH} \
  ca-certificates:${TARGET_ARCH} \
  dns-root-data:${TARGET_ARCH} \
  openssl:${TARGET_ARCH}  \
  tzdata:${TARGET_ARCH} \
  tree:${TARGET_ARCH}

strip --strip-all "/usr/local/sbin/unbound"
strip --strip-all "/usr/local/sbin/unbound-checkconf"
strip --strip-all "/usr/local/sbin/unbound-control"
strip --strip-all "/usr/local/sbin/unbound-host"
strip --strip-all "/usr/local/sbin/unbound-anchor"

"/usr/local/sbin/unbound-anchor" -a "/usr/local/etc/unbound/root.key" || true
"/usr/local/sbin/unbound-control-setup"
"/usr/local/sbin/unbound" -V

chown --recursive root:root "/etc/nsswitch.conf" "/etc/ssl/certs/ca-certificates.crt" "/usr/share/zoneinfo" "/usr/share/dns/root.hints" "/usr/local/bin" "/usr/local/etc"
chmod --recursive ugo=rX "/etc/nsswitch.conf" "/etc/ssl/certs/ca-certificates.crt" "/usr/share/zoneinfo" "/usr/share/dns/root.hints" "/usr/local/bin" "/usr/local/etc"
EOF
############################## STAGE 2 ##############################


############################## STAGE 3 ##############################
FROM --platform=${TARGETPLATFORM} scratch AS release

## nsswitch
COPY --from=build-generic \
  "/etc/nsswitch.conf" \
  "/etc/nsswitch.conf" 
## certificates
COPY --from=build-generic \
  "/etc/ssl/certs/ca-certificates.crt" \
  "/etc/ssl/certs/ca-certificates.crt"
## timezone
ENV ZONEINFO=/usr/share/zoneinfo
COPY --from=build-generic \
  "/usr/share/zoneinfo" \
  "/usr/share/zoneinfo"

ARG UNBOUND_VERSION
LABEL org.opencontainers.image.description="Unbound is a validating, recursive, caching DNS resolver. It is designed to be fast and lean and incorporates modern features based on open standards."
LABEL org.opencontainers.image.title="Unbound"
LABEL org.opencontainers.image.url="https://github.com/NLnetLabs/unbound"
LABEL org.opencontainers.image.version="$UNBOUND_VERSION"


ARG LIBMNL_VERSION
ARG OPENSSL_VERSION
LABEL libmnl.version="$LIBMNL_VERSION"
LABEL openssl.versiob="${OPENSSL_VERSION}"
LABEL unbound.version="$UNBOUND_VERSION"

## Unbound
COPY --from=build-generic \
  /usr/local/sbin \
  /usr/local/sbin
COPY --from=build-generic \
  /usr/local/etc/unbound \
  /usr/local/etc/unbound
## DNS Root Data
COPY --from=build-generic \
  /usr/share/dns/root.hints \
  /usr/share/dns/root.hints

ADD ./unbound.conf /usr/local/etc/unbound/unbound.conf

WORKDIR /usr/local/etc/unbound

USER 10000:10000

ENTRYPOINT [ "/usr/local/sbin/unbound" ]
CMD [ "-dpc", "/usr/local/etc/unbound/unbound.conf" ]

HEALTHCHECK \
  --interval=1m \
  --timeout=10s \
  --start-period=1m \
  --retries=3 \
  CMD [ \
    "/usr/local/sbin/unbound-host", \
    "-ddC", "/usr/local/etc/unbound/unbound.conf", \
    "www.google.com" \
  ]
############################## STAGE 3 ##############################
