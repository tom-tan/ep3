FROM alpine:3.11

RUN apk --no-cache add ruby ruby-json ruby-etc entr nodejs jq docker-cli \
                       ruby-irb ruby-webrick \
                       python3 git

RUN apk --no-cache add --virtual dev \
        gcc musl-dev make ruby-dev python3-dev

RUN gem install -N fluentd
RUN pip3 install cwltest

RUN apk del dev

RUN git clone --depth 1 https://github.com/common-workflow-language/common-workflow-language.git /cwl
