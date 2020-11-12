FROM alpine:3.12.0 AS medal-dev

WORKDIR /work

RUN apk --no-cache add dub ldc git gcc musl-dev && \
    git clone --depth 1 https://github.com/tom-tan/medal.git

WORKDIR medal

RUN dub build -b release-static

FROM ubuntu:20.04

LABEL maintainer="Tomoya Tanjo <ttanjo@gmail.com>"

COPY --from=medal-dev /work/medal/bin/medal /usr/bin/medal

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update &&
    apt-get -y --no-install-recommends install \
                        ruby nodejs jq ruby-dev gcc make libc-dev && \
    gem install -N fluentd && \
    apt-get purge -y ruby-dev gcc make libc-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY . /ep3

ENV PATH /ep3:$PATH
