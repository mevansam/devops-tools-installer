#!/bin/bash

script_dir=$(cd $(dirname $0) && pwd)

set -e

usage () {
    echo -e "\nUSAGE: install.sh -e|--environment <ENVIRONMENT> \\"
    echo -e "                  [ -i|--iaas <IAAS_NAME> -r|--registry <REGISTRY_DNS> -u|--user <USER_NAME> -p|--password <PASSWORD> ] \\"
    echo -e "                  [ -t|--tools <PRODUCT_LIST> ] [ -x|--uninstall ]\n"
    echo -e "    This utility will install the 'devops' tools using images and charts uploaded to the"
    echo -e "    given private registry. It will also deploy Helm's tiller container to the kubernetes"
    echo -e "    cluster if has not been deployed.\n"
    echo -e "    -e|--environment <ENVIRONMENT>  The namespace environment to deploy devops tools to."
    echo -e "    -i|--iaas <IAAS_NAME>           The underlying IAAS for allocating IAAS specific resource such as persistent volumes."
    echo -e "    -r|--registry <REGISTRY_DNS>    The FQDN or IP of the registry."
    echo -e "    -u|--user <USER_NAME>           The name of the user to use to authenticate with private registry"
    echo -e "    -p|--password <PASSWORD>        The password of the user."
    echo -e "    -t|--tools <PRODUCT_LIST>       Comma separated list of tools to install or uninstall."
    echo -e "                                    If not provided then all the tools will be deployed."
    echo -e "    -x|--uninstall                  Uninstalls the tool.\n"
    echo -e "    Options --iaas, --registry, --username and --password are required for install.\n"
}

create_uaa_client() {

  uaa_url=$1
  admin_client_secret=$2
  client_id=$3
  client_secret=$4
  scopes=$5
  redirect_uri=$6

  uaac target --skip-ssl-validation $uaa_url
  uaac token client get admin -s $admin_client_secret

  uaac client get $client_id  >/dev/null 2>&1 || \
    uaac client add $client_id \
      --name "$client_id" \
      --secret "$client_secret" \
      --scope "$scopes" \
      --authorities uaa.none \
      --authorized_grant_types authorization_code,refresh_token,password \
      --access_token_validity 3600 \
      --refresh_token_validity 7200 \
      --redirect_uri "$redirect_uri"
}

action=install
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
    -u|--user)
      user=$2
      shift
      ;;
    -p|--password)
      password=$2
      shift
      ;;
    -t|--tools)
      tools=$2
      shift
      ;;
    -x|--uninstall)
      action=uninstall
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z $environment \
  || ( $action == install \
    && ( -z $iaas \
      || -z $registry \
      || -z $user \
      || -z $password ) ) ]]; then

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

###############
# Common Values
###############

install_config=${script_dir}/.install
common_config=${script_dir}/config/common
mkdir -p $install_config

env_domain=${ENV_DOMAIN:-}

postgresql_image_version=${POSTGRESQL_IMAGE_VERSION:-11.2.0}
postgresql_chart_version=${POSTGRESQL_CHART_VERSION:-3.15.0}
postgresql_config=${script_dir}/config/postgresql

redis_image_version=${REDIS_IMAGE_VERSION:-5.0.4}
redis_chart_version=${REDIS_CHART_VERSION:-6.4.3}
redis_config=${script_dir}/config/redis

minio_image_version=${MINIO_IMAGE_VERSION:-RELEASE.2019-03-20T22-38-47Z}
minio_mc_image_version=${MINIO_MC_IMAGE_VERSION:-RELEASE.2019-03-20T21-29-03Z}
minio_chart_version=${MINIO_CHART_VERSION:-2.4.9}
minio_config=${script_dir}/config/minio

# Interpolate common k8s and helm resource declaration files

eval "echo \"$(cat ${common_config}/namespace.yml)\"" \
  > ${install_config}/namespace.yml

# Create common k8s and helm resources

if [[ -z `kubectl get pods -n kube-system | awk '/^tiller-/{ print $1 }'` ]]; then
  # Install tiller offline
  # https://github.com/helm/helm/issues/4540

  tiller_version=${TILLER_VERSION:-v2.13.0}

  echo -e "\n*** Resetting helm..."
  set +e
  kubectl delete \
    -f ${common_config}/tiller-service-account.yml \
    >/dev/null 2>&1
  set -e
  helm reset --force

  echo -e "\n*** Initializing helm.."
  helm init \
    --tiller-image ${registry}/releng/tiller:${tiller_version}

  kubectl create \
    -f ${common_config}/tiller-service-account.yml
else
  helm init --client-only >/dev/null 2>&1
fi

if [[ -z `kubectl get namespaces | awk "/^${environment} /{ print \$1 }"` ]]; then
  kubectl create \
    --filename ${install_config}/namespace.yml

  kubectl set subject clusterrolebinding tiller --serviceaccount=${environment}:tiller
  kubectl set subject clusterrolebinding tiller --serviceaccount=${environment}:default
fi

if [[ $action == install ]]; then
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

  helm_deployments=$(helm list)
fi

for t in $(echo $tools | sed 's|,| |g'); do
  eval "source ${script_dir}/install-$t.sh $action"
done
