FROM alpine:3.13.0

LABEL maintainer="Tomoya Tanjo <ttanjo@gmail.com>"

ARG medal_ver=v0.4.3
ARG medal_hook_ver=v0.1.1

RUN echo "@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    apk --no-cache add ruby ruby-json ruby-etc nodejs jq docker-cli \
                       ruby-irb ruby-webrick bash curl \
                       telegraf util-linux fluent-bit@testing && \
    curl -SL https://github.com/tom-tan/medal/releases/download/${medal_ver}/medal-linux-x86_64.tar.gz \
        | tar xC /usr/bin && \
    curl -SL https://github.com/tom-tan/medal-hook/releases/download/${medal_hook_ver}/medal-hook-linux-x86_64.tar.gz \
        | tar xC /usr/bin

COPY . /ep3

ENV PATH /ep3:$PATH
