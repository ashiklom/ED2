ROM ed-depends

ARG MODEL_VERSION="develop"
ARG PLATFORM="docker"

COPY ED /ED

WORKDIR /ED/build
RUN MAKE="make -j4" ./install.sh -k E -p docker -g
RUN ln -fs /ED/build/ed_2.1-opt /usr/local/bin/ed2.${MODEL_VERSION}

ENV RABBITMQ_QUEUE "ED2_${MODEL_VERSION}"
ENV APPLICATION "./job.sh"
