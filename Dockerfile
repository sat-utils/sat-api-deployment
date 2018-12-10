# required envvars
# - ES_HOST: Elasticsearch https endpoint

FROM satutils/sat-api:latest

WORKDIR /home/satapi-deployment

COPY package.json /home/satapi-deployment/

RUN \
    yarn; yarn linkall

COPY . /home/satapi-deploy