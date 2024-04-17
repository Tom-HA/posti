FROM ubuntu:latest

RUN apt update
RUN apt install curl build-essential sudo -y
RUN curl -LO https://ftp.gnu.org/gnu/bash/bash-3.2.tar.gz
RUN tar -xf bash-3.2.tar.gz
WORKDIR /bash-3.2
RUN ./configure
RUN make
RUN make install
WORKDIR /

ENTRYPOINT /usr/local/bin/bash
