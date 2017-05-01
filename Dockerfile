FROM library/ubuntu:latest

# Update packages
RUN apt-get -y update && apt-get -y upgrade

# Install packages
RUN apt-get -y install gfortran make gdb libhdf5-openmpi-dev
RUN apt-get -y install git

# Copy ED2
COPY . /ED2

# Install ED2
RUN /bin/bash -c 'cd /ED2/ED/build; ./install.sh -k A -p ubuntu --gitoff'

# This is the command that is run by default
# when executing `docker run`
CMD ["/ED2/ED/build/ed_2.1-dbg -f /edinputs/ED2IN"]

