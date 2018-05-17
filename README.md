# Letsencrypt Pipeline for PCF on GCP
This is a [concourse pipeline](https://concourse-ci.org/) that performs the following actions:

1. Checks if your current PCF certificate is about to expire
2. Requests new wildcard certificates from letsencrypt
3. Updates the Google Load Balancer
4. Updates the following PCF components:
	* PAS
	* PKS
	* VMware Harbor

## Getting Started
You should have your DNS delegated to GCP in the same project as PCF is installed.

You should then move the file `credentials-sample.yml` to `credentials.yml` and edit the fields for your environment. This file is self-documented.

One that is done and you are logged in to concourse, create the pipeline:

```
% fly -t <concourse-server> set-pipeline -p le-for-pcf-on-gcp-pipeline -c pipeline.yml -l credentials.yml
```

By default it will trigger every 24 Hours and check if your current certificate is out of date. If it is, it will go ahead and do all the work for you.

## Docker Image
The scripts use the custom docker image `mattsday/le-pcf-on-gcp-base`, the source for which you can find in the `docker-base-img/` folder.
