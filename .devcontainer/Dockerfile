FROM alpine:3.12

RUN apk --no-cache add ruby ruby-json ruby-etc nodejs jq docker-cli \
                       ruby-irb ruby-webrick \
                       python3 py3-pip git bash curl gnupg

RUN pip3 install cwltest
