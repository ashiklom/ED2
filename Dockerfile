FROM debian:jessie
# FROM edtest:latest

ARG MODEL_VERSION "develop"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gfortran \
        git \
        libhdf5-dev \
        libopenmpi-dev \
        gdb && rm -rf /var/lib/apt/lists/*

COPY ED /ED

WORKDIR /ED/build
RUN MAKE=make -j4 ./install.sh -k E -p docker -g
RUN ln -fs /ED/build/ed_2.1-opt /usr/local/bin/ed2.${MODEL_VERSION}

ENV RABBITMQ_QUEUE "ED2_${MODEL_VERSION}"
ENV APPLICATION "./job.sh"
