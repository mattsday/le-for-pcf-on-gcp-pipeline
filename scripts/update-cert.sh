#!/bin/bash

if [ -z "${GCP_CREDENTIALS}" ]; then echo No GCP_CREDENTIALS; exit 1; fi
if [ -z "${CF_DOMAINS}" ]; then echo No CF_DOMAINS; exit 1; fi
if [ -z "${LE_EMAIL}" ]; then echo No LE_EMAIL; exit 1; fi
if [ -z "${LE_SERVER}" ]; then export LE_SERVER="https://acme-v02.api.letsencrypt.org/directory"; fi
if [ -z "${GCP_CREDENTIALS_FILE}" ]; then export GCP_CREDENTIALS_FILE="/accounts.json"; fi
if [ -z "${PCF_USER}" ]; then echo Setting \$PCF_USER to admin; PCF_USER=admin; fi
if [ -z "${PCF_OPSMGR}" ]; then echo NO PCF_OPSGR set; exit 1; fi
if [ -z "${PCF_PASSWD}" ]; then echo Please enter your PCF Ops Manager password for $PCF_USER; exit 1; fi
if [ -z "${GCP_CERT_NAME}" ]; then GCP_CERT_NAME=pcf-cert-$(uuid); echo Setting \$GCP_CERT_NAME to ${GCP_CERT_NAME}; fi
if [ -z "${GCP_HTTPS_PROXY}" ]; then echo No GCP_HTTPS_PROXY; exit 1; fi
if [ -z "${OPSMAN_CERT_NAME}" ]; then echo Setting OPSMAN_CERT_NAME to Certificate; OPSMAN_CERT_NAME=Certificate; fi
if [ -z "${GCP_DNS_WAIT}" ]; then echo Setting DNS Propogation wait timer to 120; GCP_DNS_WAIT=120; fi
if [ -z "${SKIP_PAS_CERT}" ]; then echo Updating PAS Certificate by default; SKIP_PAS_CERT=false; fi
if [ -z "${SKIP_PKS_CERT}" ]; then echo Updating PKS Certificate by default; SKIP_PKS_CERT=false; fi
if [ -z "${SKIP_HARBOR_CERT}" ]; then echo Updating Harbor Certificate by default; SKIP_HARBOR_CERT=false; fi
if [ -z "${SKIP_GCP_CERT}" ]; then echo Updating GCP Certificate by default; SKIP_GCP_CERT=false; fi
if [ -z "${SKIP_OPSMAN_APPLY}" ]; then echo Applying changes in ops manager by default; SKIP_OPSMAN_APPLY=false; fi

echo ${GCP_CREDENTIALS} | tee ${GCP_CREDENTIALS_FILE} >/dev/null

export PATH="$PATH:/google-cloud-sdk/bin"

GCP_PROJECT_ID=$(cat ${GCP_CREDENTIALS_FILE} | jq -r '.project_id')
gcloud config set project ${GCP_PROJECT_ID} 

echo Generating certificate

certbot certonly -n --agree-tos --email ${LE_EMAIL} \
  --dns-google-propagation-seconds ${GCP_DNS_WAIT} \
  --dns-google --dns-google-credentials ${GCP_CREDENTIALS_FILE} \
  -d ${CF_DOMAINS} \
  --server ${LE_SERVER} \
  --cert-path / \
  --cert-name le

if [ ! -f "/etc/letsencrypt/live/le/fullchain.pem" ] || \
   [ ! -f "/etc/letsencrypt/live/le/privkey.pem" ]; then
	echo No certificate generated see logs
	exit 1
fi

PUB_CERT=/etc/letsencrypt/live/le/fullchain.pem
PRIV_KEY=/etc/letsencrypt/live/le/privkey.pem

if [ ${SKIP_GCP_CERT} = false ]; then
	echo Updating Google Load Balancer Certificate
	# Create cert in GCP
	gcloud auth activate-service-account --key-file=${GCP_CREDENTIALS_FILE}

	if [ $? -ne 0 ]; then
		echo Logging in to GCP failed
		exit 1;
	fi

	gcloud compute ssl-certificates create ${GCP_CERT_NAME} --certificate=${PUB_CERT} --private-key=${PRIV_KEY} --description="Letsencrypt cert updated $(date)"
	gcloud compute target-https-proxies update ${GCP_HTTPS_PROXY} --ssl-certificates=${GCP_CERT_NAME}
else
	echo Skipping updating Google Load Balancer Certificate

fi
format_cert() {
	echo ${1//$'\n'/'\n'}
}

FULL_CHAIN=$(format_cert "$(cat ${PUB_CERT})")
PRIV_KEY=$(format_cert "$(cat ${PRIV_KEY})")

if [ ${SKIP_PAS_CERT} = false ]; then
	echo Updating PAS Certificate
	CF_JSON=$(echo "{
		\".properties.networking_poe_ssl_certs\": {
		    \"value\": [{
				\"certificate\": {
					\"cert_pem\": \"${FULL_CHAIN}\",
					\"private_key_pem\": \"${PRIV_KEY}\"
				},
				\"name\": \"${OPSMAN_CERT_NAME}\"
			}]
		}
	}" | jq -c -M '.')
	om -k -u "${PCF_USER}" -p "${PCF_PASSWD}" -t "${PCF_OPSMGR}" configure-product --product-name cf -p "${CF_JSON}"
else
	echo Skipping updating PAS Certificate
fi

if [ ${SKIP_HARBOR_CERT} = false ]; then
	echo Updating Harbor Certificate
	HARBOR_JSON=$(echo "{
		\".properties.server_cert_key\": {
		    \"value\": {
				\"cert_pem\": \"${FULL_CHAIN}\",
				\"private_key_pem\": \"${PRIV_KEY}\"
			}
		},
		\".properties.server_cert_ca\": {
			\"value\": \"${FULL_CHAIN}\"
		}
	}" | jq -c -M '.')
	
	om -k -u "${PCF_USER}" -p "${PCF_PASSWD}" -t "${PCF_OPSMGR}" configure-product --product-name harbor-container-registry -p "${HARBOR_JSON}"
else
	echo Skipping updating Harbor Certificate
fi

if [ ${SKIP_PKS_CERT} = false ]; then
	echo Updating PKS Certificate
	PKS_JSON=$(echo "{
		\".pivotal-container-service.pks_tls\": {
		    \"value\": {
				\"cert_pem\": \"${FULL_CHAIN}\",
				\"private_key_pem\": \"${PRIV_KEY}\"
			}
		}
	}" | jq -c -M '.')
	
	om -k -u "${PCF_USER}" -p "${PCF_PASSWD}" -t "${PCF_OPSMGR}" configure-product --product-name pivotal-container-service -p "${PKS_JSON}"
else
	echo Skipping updating PKS Certificate
fi

if [ ${SKIP_OPSMAN_APPLY} = false ]; then
	echo Applying ops manager changes
	om -k -u "${PCF_USER}" -p "${PCF_PASSWD}" -t "${PCF_OPSMGR}" apply-changes
else
	echo Skipping applying ops manager changes
fi
