FROM alpine:3.13

ARG USERNAME=ep3
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN apk --no-cache add sudo shadow \
    && groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

RUN apk --no-cache add ruby ruby-json ruby-etc nodejs jq docker-cli \
                       ruby-irb ruby-webrick \
                       python3 py3-pip git bash curl gnupg

RUN pip3 install cwltest

USER $USERNAME
