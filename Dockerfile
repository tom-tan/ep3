FROM alpine:3.12.0 AS medal-dev

WORKDIR /work

RUN apk --no-cache add dub ldc git gcc musl-dev && \
    git clone --depth 1 https://github.com/tom-tan/medal.git

WORKDIR medal

RUN dub build -b release && \
    strip bin/medal

FROM alpine:3.12.0

LABEL maintainer="Tomoya Tanjo <ttanjo@gmail.com>"

COPY --from=medal-dev /work/medal/bin/medal /usr/bin/medal

RUN apk --no-cache add ruby ruby-json ruby-etc nodejs jq docker-cli \
                       ruby-irb ruby-webrick

COPY . /ep3

ENV PATH /ep3:$PATH
