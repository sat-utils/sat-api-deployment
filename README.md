# sat-api-deployment

This deployment powers https://sat-api.developmentseed.org/stac. We use [kes](https://www.npmjs.com/package/kes) to deploy sat-api as an application to AWS.

For the deployment to work we use a kes template included in the [@sat-utils/api](https://www.npmjs.com/package/@sat-utils/api) package. This package has all the necessary resources needed for a successful deployment of sat-api.

You can override all the configurations and options in this template by modifying the `.kes/config.yml` folder.

## Install

     $ yarn install

## Deploy with unpublished code

If you need to use the latest code on the master branch that is not released to npm yet, or if you need to do live development on an instance deployed to AWS (not recommended), you should follow these steps:

- Clone this repo and install requirements ([follow](../README.md#local-installation))
- At the repo root run: `yarn linkall` (this will link packages to your local npm).
- In the deployment repository (e.g. `example` folder) run the link command with the package name you are using:
    - `yarn link @sat-utils/api`
    - In the `example` folder we have included a shortcut: `yarn linkall`
- Verify packages are linked: `ls -la node_modules/@sat-utils`
    - This show an output similar to: `lrwxr-xr-x 1 user staff 29 Jul 11 14:19 api -> ../../../sat-api/packages/api`

To restore packages from npm just run `yarn`.

## Deploy an instance

Make sure the you add a deployment to `.kes/config.yml` by adding the following to the file:

```yaml
name-of-my-deployment:
  stackName: <name-of-my-stack>
  system_bucket: <a s3 bucket I have access to>
```

Then run this command:

     $ ./node_modules/.bin/kes cf deploy --region us-east-1 --profile <profile-name> --template node_modules/@sat-utils/api/template --deployment <name-of-deployment> --showOutputs

The command will return the api endpoint that is created by the operation.


### Deployer Role

For the CI environment, we use a special IAM role that is assumed by an AWS user. This will allow us to give limited access to the user that is used inside the CI build environment.

To create the deployer role run:

     $ ./node_modules/.bin/kes cf deploy --kes-folder deployer --profile ds --region us-east-1 --showOutputs

Then create a user on AWS and give it this policy permission. Replace the value of the resource with the output of the previous command:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": "<arn:DeployerRole>"
        }
    ]
}
```

When running the deployment command make sure to [include the `--role` flag](.circleci/config.yml#L17).


## Allow access to Kibana

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

### Ingest collections

### Adding SNS subscription

The sat-api ingest function can be used to ingest SNS messages of two types:
- An s3 updated message
- The STAC record itself

There are several public datasets that publish the complete STAC record to an SNS topic:
  - Landsat-8 L1: arn:aws:sns:us-west-2:552188055668:landsat-stac
  - Sentinel-2 L1:

Once subscribed any future SNS messages will be ingested into the backend and be immediately available to the API.

### Ingesting catalogs

In order to backfill data a STAC static catalog can be ingested starting from any node in the catalog. Child links within catalogs will be followed and any Collection or Item will be ingested. To ingest a catalog the ingest Lambda is invoked with a payload including a "url" field, along with some optional parameters:

- **url** (required): The http(s) URL to a node in a static STAC (i.e., a Catalog, Collection, or Item).
- **recursive**: If set to false, child links will not be followed from the input catalog node. *Defaults to true.*
- **collectionsOnly**: If set to true, only Collections will be ingested. Child links will be followed until a Collection is found and ingested. It is assumed Collections do not appear below other Collections within a STAC tree. *Defaults to false.*

### Using Fargate to run large ingestion jobs

When ingesting a catalog using the URL field, the Lambda function will attempt the ingest. However the time required for any sizable catalog may be longer than the maximum allowed by Lambda functions (15 minutes). In those cases the ingest job can be spawned, from the Lambda function, as a Fargate task. This fires up a Fargate instance using a Docker image containing the sat-api code and runs the ingest task on the provided URL, and there is no time limit. To run Ingest as a Fargate the normal parameters for ingesting a catalog are simply provided nested under the "fargate" field. While this means that the recursive and collectionsOnly fields can be provided to a Fargate task, the reality is that not using the defaults for these parameters means that your ingest task will very likely fit within the time limit for Lambda functions. Therefore, Fargate tasks will typically just contain the path a STAC node to be traversed and everything undernearth it will be ingested.

```
{
    "fargate": {
        "url": "url/to/catalog.json"
    }
}
