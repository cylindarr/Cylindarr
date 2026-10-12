# ================================
# Build image
# ================================
# Swift 6.3 on Ubuntu 24.04 (noble).
FROM swift:6.3-noble AS build

WORKDIR /build
# Resolve first so dependencies cache independently of source changes.
COPY Package.* ./
COPY CylindarrAPI ./CylindarrAPI
RUN swift package resolve

COPY . .
RUN swift build -c release --product App --static-swift-stdlib

# ================================
# Run image
# ================================
# Noble, the build image's own release: FoundationXML (the feed parser) links
# libxml2.so.2, which 26.04 has replaced with a new soname.
FROM ubuntu:24.04

ARG TARGETARCH
# Pinned, and each moved on purpose. yt-dlp is also updated at run time by
# Cylindarr itself; this is the version a fresh container starts with.
ARG YTDLP_VERSION=2026.08.19
ARG DENO_VERSION=v2.9.7
ARG BGUTIL_VERSION=2.0.0
# SHA-256 of the Deno and bgutil downloads. Change them with the versions
# above; GitHub shows each release asset's digest.
ARG DENO_SHA256_AMD64=c6527f24f4b16031d3ae4fa9f658d5f11534c8d84ce7dc8502420280919c3490
ARG DENO_SHA256_ARM64=c832298b1ad4422481334855f6003e0f54145762c5a134f20a489511d2f65bbf
ARG BGUTIL_SHA256=bce874dfa25896c2798e0f4f8147b7b22e785479eb1e459ab232bf2506c95016

# ffmpeg merges, cuts SponsorBlock segments and encodes to HEVC. curl is for
# the healthcheck and the downloads below. unzip for Deno and nothing else.
# On amd64, the drivers for encoding on a GPU passed in as /dev/dri: Intel's
# media driver and oneVPL runtime for Quick Sync, and Mesa's VA-API drivers
# for AMD. NVENC needs nothing here; the NVIDIA container runtime brings the
# driver's libraries in. Without a GPU, Cylindarr encodes on the CPU.
RUN apt-get -qq update \
    && case "$TARGETARCH" in arm64) GPU="" ;; *) GPU="intel-media-va-driver-non-free libmfx-gen1.2 mesa-va-drivers" ;; esac \
    && DEBIAN_FRONTEND=noninteractive apt-get -q install -y --no-install-recommends \
        ca-certificates tzdata curl ffmpeg unzip libxml2 $GPU \
    && rm -rf /var/lib/apt/lists/*

# yt-dlp's standalone build: no Python in the image. Checked against the
# release's own checksums; Deno and bgutil against the pins above.
RUN set -eux; \
    case "$TARGETARCH" in \
      arm64) YT=yt-dlp_linux_aarch64; DENO=deno-aarch64-unknown-linux-gnu; DENO_SHA256=$DENO_SHA256_ARM64 ;; \
      *) YT=yt-dlp_linux; DENO=deno-x86_64-unknown-linux-gnu; DENO_SHA256=$DENO_SHA256_AMD64 ;; \
    esac; \
    mkdir -p /app/bin /etc/yt-dlp/plugins; \
    curl -fsSL -o /tmp/$YT "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/$YT"; \
    curl -fsSL -o /tmp/SUMS "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/SHA2-256SUMS"; \
    (cd /tmp && grep " $YT\$" SUMS | sha256sum -c -); \
    install -m 755 /tmp/$YT /app/bin/yt-dlp; \
    curl -fsSL -o /tmp/deno.zip "https://github.com/denoland/deno/releases/download/${DENO_VERSION}/$DENO.zip"; \
    echo "$DENO_SHA256  /tmp/deno.zip" | sha256sum -c -; \
    unzip -q /tmp/deno.zip -d /usr/local/bin; chmod 755 /usr/local/bin/deno; \
    curl -fsSL -o /etc/yt-dlp/plugins/bgutil-ytdlp-pot-provider.zip \
      "https://github.com/Brainicism/bgutil-ytdlp-pot-provider/releases/download/${BGUTIL_VERSION}/bgutil-ytdlp-pot-provider.zip"; \
    echo "$BGUTIL_SHA256  /etc/yt-dlp/plugins/bgutil-ytdlp-pot-provider.zip" | sha256sum -c -; \
    rm -rf /tmp/*

RUN useradd --user-group --create-home --system --home-dir /app vapor && chmod 755 /app

WORKDIR /app
COPY --from=build --chown=vapor:vapor /build/.build/release/App /app/App
COPY --from=build --chown=vapor:vapor /build/Resources /app/Resources
COPY --from=build --chown=vapor:vapor /build/Public /app/Public

# The database, the cookie jar and any yt-dlp the updater has fetched. The
# only thing here that is not rebuilt from the library.
RUN mkdir -p /app/data && chown vapor:vapor /app/data
ENV CYLINDARR_DATA=/app/data

USER vapor:vapor
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -fsS http://localhost:8080/health || exit 1

ENTRYPOINT ["/app/App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
