# Base image version ##########
ARG IMAGE_VERSION="local"

# Compile model ################

FROM debian:stretch as model-binary

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    git \
    gfortran \
    libhdf5-dev \
    libopenmpi-dev && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /ed_source/build/make \
            /ed_source/build/shell \
            /ed_source/src
            
COPY ED/src/ /ed_source/src/
COPY ED/build/make/ /ed_source/build/make
COPY ED/build/shell /ed_source/build/shell
COPY ED/build/install.sh /ed_source/build/

ARG MAKE=${MAKE:-make}
ARG INSTALL_KIND="A"

RUN echo "Install kind: ${INSTALL_KIND}" && \
    cd /ed_source/build && ./install.sh -g -p docker -k ${INSTALL_KIND}

RUN if [ ${INSTALL_KIND} = "E" ]; \
    then EXT=opt; \
    else EXT=dbg; \
    fi && \
    cp /ed_source/build/ed_2.1-${EXT} /ed_source/build/ed_2.1-exe

# Install model in correct location ##############

FROM pecan/models:${IMAGE_VERSION}
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libgfortran3 \
        libopenmpi2 \
    && rm -rf /var/lib/apt/lists/*

ARG MODEL_VERSION=develop

COPY model_info.json /work/model.json
RUN sed -i -e "s#@VERSION@#${MODEL_VERSION}#g" \
           -e "s#@BINARY@#/usr/local/bin/ed2.${MODEL_VERSION}#g" /work/model.json

ENV MODEL_VERSION="develop"

COPY --from=model-binary /ed_source/build/ed_2.1-exe /usr/local/bin/ed2.${MODEL_VERSION}
