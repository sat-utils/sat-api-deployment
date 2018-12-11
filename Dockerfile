# required envvars
# - ES_HOST: Elasticsearch https endpoint

FROM satutils/sat-api:develop

WORKDIR ${HOME}/satapi-deployment

COPY package.json ./

RUN \
    yarn; yarn linkall

COPY . ${HOME}/satapi-deployment