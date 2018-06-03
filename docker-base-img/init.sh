#!/bin/bash
apt-get update && apt-get -y dist-upgrade && apt-get -y install git python python-pip build-essential libffi-dev libssl-dev wget jq uuid && apt-get clean && rm -rf /var/lib/apt/lists/*

pip install cryptography==2.2.1 certbot certbot-dns-google

wget "https://github.com/pivotal-cf/om/releases/download/0.36.0/om-linux" -O /usr/local/bin/om
chmod +x /usr/local/bin/om

wget "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-200.0.0-linux-x86_64.tar.gz" -O cloud-sdk.tar.gz
tar zxvf cloud-sdk.tar.gz
rm cloud-sdk.tar.gz
cd google-cloud-sdk || exit 1
./install.sh --usage-reporting false -q

cd / || exit 1

/google-cloud-sdk/bin/gcloud components update --quiet

