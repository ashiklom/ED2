FROM ed-depends

ARG MODEL_VERSION="develop"
ARG PLATFORM="docker"
ARG KIND="E"
ARG SUFFIX="opt"

COPY ED /ED

WORKDIR /ED/build
RUN MAKE="make -j4" ./install.sh -k ${KIND} -p ${PLATFORM} -g
RUN ln -fs /ED/build/ed_2.1-${SUFFIX} /usr/local/bin/ed2.${MODEL_VERSION}

ENV RABBITMQ_QUEUE "ED2_${MODEL_VERSION}"
ENV APPLICATION "./job.sh"
