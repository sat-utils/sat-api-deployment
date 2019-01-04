# sat-api-deployment

This deployment powers https://sat-api.developmentseed.org/stac, but can also be used as an example template to create your own deployment.

We use [kes](https://www.npmjs.com/package/kes) to deploy sat-api as an application to AWS. A kes template included in the [@sat-utils/api](https://www.npmjs.com/package/@sat-utils/api) package is used which has all the necessary resources needed.

## Install

First, clone this repo and update any appropriate fields in the package.json file. This is where you can change the version of sat-api used if needed. Then install the dependencies:

     $ yarn

If you need to use the development branch of sat-api that is not yet released on NPM follow these steps.

- Install sat-api locally from [the develop branch](https://github.com/sat-utils/sat-api).
- In the sat-api repo run: `yarn linkall` (this will link packages to your local npm).
- In this deployment repository link to your local version of sat-api: `yarn linkall`

To restore packages from npm just run `yarn`.

## Deploy an instance

You will first need to edit the `.kes/config.yml` file, which includes two deployments: production (prod) and development (dev). in the default section:

```yaml
default:
  system_bucket: sat-api-us-east-1

  tags:
    project: sat-api

  lambdas:
    api:
      envs:
        STAC_TITLE: "sat-api for public datasets"
        STAC_ID: "sat-api"
        STAC_VERSION: "0.6.0"
        STAC_DESCRIPTION: "sat-api for public datasets by Development Seed"
    ingest:
      envs:
        SUBNETS: "subnet-151f3719 subnet-3dd20e76 subnet-53776a7f subnet-c641579c subnet-dc358bb8 subnet-ef13ced0"
        SECURITY_GROUPS: "sg-b0ef3ac2"
        ES_BATCH_SIZE: 1000
```

Make the following changes:

- change `system_bucket` to a bucket name for which you have access to. This is used for uploading Lambda function code packages.
- Set any `tags` to be applied to all resources created in the stack
- Update the environment variables under `lambdas:api:envs` with details about your API
- Update `lambdas:ingest:envs:SUBNETS` with a list of subnet IDs in your AWS account for use with Fargate
- Update `lambdas:ingest:envs:SUBNETS` to a security group ID in your account for use with Fargate
- `ES_BATCH_SIZE` is a good default for writing to Elasticsearch from Lambda or Fargate to a bucket in the same region. It should not be set to higher than 2000 due to a total payload size limit with Elasticsearch.

After changing the defaults review the settings for each of the deployments:

```yaml
dev:
  stackName: sat-api-dev
  es:
    instanceCount: 2
    instanceType: m3.medium.elasticsearch
    volumeSize: 80
  tasks:
    SatApi:
      image: satutils/sat-api:develop

prod:
  stackName: sat-api-prod
  es:
    instanceCount: 2
    instanceType: m3.medium.elasticsearch
    volumeSize: 80
```

Each deployment must have `stackName` set, but there is little need to change any of the other settings here. The Elasticsearch instance size is a good default starting value. `tasks:SatApi:image` indicates a dev deployment should use the develop version of sat-api. Remove this entirely to have dev (if used at all) use the same sat-api version.

Additional deployments can be added by adding the relevant section.

```yaml
name-of-my-deployment:
  stackName: <name-of-my-stack>
```

### Deploy!

Run this command to deploy a stack:

     $ ./node_modules/.bin/kes cf deploy --region us-east-1 --profile <profile-name> --template node_modules/@sat-utils/api/template --deployment <name-of-deployment> --showOutputs

The command will return the API endpoint that is created by the operation.

### Allow access to Kibana

For development purposes you may want to access the Elasticsearch Kibana interface from your local machine. If so, you will need to edit the access policy to allow access from your IP. In the AWS console for the Elasticsearch that was just deployed modify the access policy and add this entry to the "Statements" array:

```json
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "es:*",
      "Resource": "arn:aws:es:<region>:<account>:domain/<stackName>-es6/*",
      "Condition": {
        "IpAddress": {
          "aws:SourceIp": "<your_ip>"
        }
      }
    }
```

## Ingesting data

Ingesting data is all handled by the Ingest Lambda function (<stackName>-ingest). It can take a number of different payloads for ingesting static STAC catalogs.

### Ingest collections from a catalog

Although the STAC specification does allow for Items to not be part of a Collection, sat-api assumes they all are. Collections don't need to be be ingested first. If a complete catalog will be ingested the Collections in that Catalog will be ingested. To ingest just Collections in a Catalog trigger the Ingest Lambda with the following payload.

```json
{
    "url": "https://a.stac.catalog/catalog.json",
    "collectionsOnly": true
}
```

### Ingest items from SNS

The sat-api ingest function can be used to ingest SNS messages of two types:
- An s3 updated event
- The STAC record itself

In the Ingest Lambda console add an SNS trigger and provide the SNS ARN. The Lambda function will now be triggered by events and will ingest either message type.

There are several public datasets that publish the complete STAC record to an SNS topic:
  - Landsat-8 L1: arn:aws:sns:us-west-2:552188055668:landsat-stac
  - Sentinel-2 L1: arn:aws:sns:eu-central-1:552188055668:sentinel-stac

Once subscribed any future SNS messages will be ingested into the backend and be immediately available to the API.

### Ingest items from a catalog

In order to backfill data a STAC static catalog can be ingested starting from any node in the catalog. Child links within catalogs will be followed and any Collection or Item will be ingested. To ingest a catalog the ingest Lambda is invoked with a payload including a "url" field, along with some optional parameters:

- **url** (required): The http(s) URL to a node in a static STAC (i.e., a Catalog, Collection, or Item).
- **recursive**: If set to false, child links will not be followed from the input catalog node. *Defaults to true.*
- **collectionsOnly**: If set to true, only Collections will be ingested. Child links will be followed until a Collection is found and ingested. It is assumed Collections do not appear below other Collections within a STAC tree. *Defaults to false.*

Ingest a complete catalog:

```json
{
    "url": "https://a.stac.catalog/catalog.json",
}
```

Ingest all items and collections from a subcatalog:

```json
{
    "url": "https://a.stac.catalog/path/to/sub/catalog.json",  
}

Ingest a single item:
```json
{
    "url": "https://a.stac.catalog/path/to/item.json",  
}
```

### Using Fargate to run large ingestion jobs

When ingesting a catalog using the URL field, the Lambda function will attempt the ingest. However the time required for any sizable catalog may be longer than the maximum allowed by Lambda functions (15 minutes). In those cases the ingest job can be spawned, from the Lambda function, as a Fargate task. This fires up a Fargate instance using a Docker image containing the sat-api code and runs the ingest task on the provided URL, and there is no time limit. To run Ingest as a Fargate the normal parameters for ingesting a catalog are simply provided nested under the "fargate" field. While this means that the recursive and collectionsOnly fields can be provided to a Fargate task, the reality is that not using the defaults for these parameters means that your ingest task will very likely fit within the time limit for Lambda functions. Therefore, Fargate tasks will typically just contain the path a STAC node to be traversed and everything undernearth it will be ingested.

```json
{
    "fargate": {
        "url": "url/to/catalog.json"
    }
}
```

The other payload parameters (recursive and collectionsOnly) can be provided and wil be honored by the Fargate task, however if only Collections or a single Item are being ingested a Fargate task is probably not needed and the Lambda function should be able to handle it.
