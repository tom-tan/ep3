FROM alpine:3.12.0

LABEL maintainer="Tomoya Tanjo <ttanjo@gmail.com>"

ARG medal_ver=v0.0.5

RUN apk --no-cache add ruby ruby-json ruby-etc nodejs jq docker-cli \
                       ruby-irb ruby-webrick bash curl && \
    curl -SL https://github.com/tom-tan/medal/releases/download/${medal_ver}/medal-linux-x86_64.tar.gz \
        | tar xC /usr/bin && \
    apk del --purge curl

COPY . /ep3

ENV PATH /ep3:$PATH
