FROM mcr.microsoft.com/vscode/devcontainers/base:0-alpine-3.13

RUN echo "@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \
    && apk --no-cache add ruby ruby-json ruby-etc nodejs docker-cli \
                          ruby-irb ruby-webrick python3 py3-pip \
                          telegraf util-linux fluent-bit@testing

RUN pip3 install cwltest

USER vscode
