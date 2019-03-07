ARG IMAGE_VERSION="local"
ARG MAKE="make"

FROM pecan/model-ed2-git:${IMAGE_VERSION}

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

RUN cd /ed_source/build && ./install.sh -g -p docker -k A

ENV APPLICATION="./job.sh"
ENV MODEL_TYPE="ED2"
ENV MODEL_VERSION="develop"
ENV RABBITMQ_QUEUE="${MODEL_TYPE}_${MODEL_VERSION}"

RUN cp /ed_source/build/ed_2.1-dbg /usr/local/bin/ed2.${MODEL_VERSION}
