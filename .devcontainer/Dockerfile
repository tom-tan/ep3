FROM alpine:3.12

RUN apk --no-cache add ruby ruby-json ruby-etc nodejs jq docker-cli \
                       ruby-irb ruby-webrick \
                       python3 py3-pip git

RUN apk --no-cache add --virtual dev \
        gcc musl-dev make ruby-dev python3-dev

RUN gem install -N fluentd
RUN pip3 install cwltest

RUN apk del dev
