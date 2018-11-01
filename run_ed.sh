#!/bin/bash

dirroot=/home/ashiklom/Projects/docker

docker run -v ${dirroot}/edinputs:/edinputs \
    -v ${dirroot}/edoutputs:/edoutputs \
    ed2docker \
    /bin/bash -c 'ulimit -s unlimited; /ED2/ED/build/ed_2.1-dbg -f /edinputs/ED2IN'
