#!/bin/bash

script_dir=$(cd $(dirname $0) && pwd)

set -e

usage () {
    echo -e "\nUSAGE: install.sh -i|--iaas <IAAS_NAME> -e|--environment <ENVIRONMENT> -r|--registry <REGISTRY_DNS>\n"
    echo -e "This utility will install all 'releng' tools using images uploaded to a private registry.\n"
    echo -e "    -i|--iaas <IAAS_NAME>           The underlying IAAS for allocating IAAS specific resource such as persistent volumes."
    echo -e "    -e|--environment <ENVIRONMENT>  The namespace environment to deploy relelease engineering services to."
    echo -e "    -r|--registry <REGISTRY_DNS>    The FQDN or IP of the registry."
    echo -e ""
}

create_uaa_client() {

  uaa_url=$1
  admin_client_secret=$2
  scopes=$3

  uaac target --skip-ssl-validation $uaa_url
  uaac token client get admin -s $admin_client_secret

  uaac client get concourse  >/dev/null 2>&1 || \
    uaac client add concourse \
      --name concourse \
      --secret "$CONCOURSE_CLIENT_SECRET" \
      --scope "$scopes" \
      --authorities uaa.none \
      --authorized_grant_types authorization_code,refresh_token,password \
      --access_token_validity 3600 \
      --refresh_token_validity 7200 \
      --redirect_uri "${CONCOURSE_EXTERNAL_URL}/sky/issuer/callback"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    '-?'|--help|help)
      usage
      exit 0
      ;;
    -v|--debug)
      set -x
      ;;
    -i|--iaas)
      iaas=$2
      shift
      ;;
    -e|--environment)
      environment=$2
      shift
      ;;
    -r|--registry)
      registry=$2
      shift
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z $iaas \
  || -z $environment \
  || -z $registry ]]; then

  usage
  exit 1
fi

ca_cert_file=${script_dir}/.certs/ca.crt
if [[ ! -e $ca_cert_file ]]; then
  echo -e "\nERROR: Please provide a CA cert file at:"
  echo -e "       $ca_cert_file"
  echo -e "       to validate self-signed TLS end-points.\n"
  exit 1
fi

case "$iaas" in
  google)
    ;;
  vsphere)
    if [[ -n $VSPHERE_DATASTORE ]]; then
      echo -e "\nERROR! Please provide the vsphere data store to use for persistent\n"
      echo -e "         volumes via 'VSPHERE_DATASTORE' environment variable.\n"
      exit 1
    fi
    ;;
  *)
    echo -e "\nERROR! IAAS must be one of 'google' or 'vsphere'.\n"
    exit 1
esac

###############
# Common Values
###############

helm_deployments=$(helm list)

postgresql_image_version=${POSTGRESQL_IMAGE_VERSION:-11.2.0}
postgresql_chart_version=${POSTGRESQL_CHART_VERSION:-3.15.0}

postgresql_pvc_size=${POSTGRESQL_VOLUME_SIZE:-50Gi}

postgresql_config=${script_dir}/config/postgresql

install_config=${script_dir}/.install
common_config=${script_dir}/config/common
mkdir -p $install_config

# Interpolate common k8s and helm resource declaration files

eval "echo \"$(cat ${common_config}/namespace.yml)\"" \
  > ${install_config}/namespace.yml

# Create common k8s and helm resources

if [[ -z `kubectl get namespaces | awk "/^${environment} /{ print \$1 }"` ]]; then
  kubectl create \
    --filename ${install_config}/namespace.yml

  kubectl set subject clusterrolebinding tiller --serviceaccount=${environment}:tiller
  kubectl set subject clusterrolebinding tiller --serviceaccount=${environment}:default
fi

# Install Concourse Helm chart
# source ${script_dir}/install-concourse.sh install

# Install Artifactory Helm chart
source ${script_dir}/install-artifactory.sh install
