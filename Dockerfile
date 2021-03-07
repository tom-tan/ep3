FROM alpine:3.13.0

LABEL maintainer="Tomoya Tanjo <ttanjo@gmail.com>"

ARG medal_ver=v0.4.0
ARG medal_hook_ver=v0.0.5

RUN apk --no-cache add ruby ruby-json ruby-etc nodejs jq docker-cli \
                       ruby-irb ruby-webrick bash curl && \
    curl -SL https://github.com/tom-tan/medal/releases/download/${medal_ver}/medal-linux-x86_64.tar.gz \
        | tar xC /usr/bin && \
    curl -SL https://github.com/tom-tan/medal-hook/releases/download/${medal_hook_ver}/medal-hook-linux-x86_64.tar.gz \
        | tar xC /usr/bin && \
    apk del --purge curl

COPY . /ep3

ENV PATH /ep3:$PATH
