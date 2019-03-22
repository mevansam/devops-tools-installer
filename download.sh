#!/bin/bash

script_dir=$(cd $(dirname $0) && pwd)

set -e

usage () {
    echo -e "\nUSAGE: download.sh [ -r|--registry <REGISTRY_DNS> ] \\"
    echo -e "                   [ -u|--user <USER_NAME> ] [ -p|--password <PASSWORD> ] \\" 
    echo -e "                   [ -c|--clean ] [ -d|--download-only ]\n"
    echo -e "    This utility will download all required artifacts to set up the devops tools. It will"
    echo -e "    upload them to a private registry such as Harbor. Downloaded images and charts will"
    echo -e "    be saved locally and re-used for off-line installs.\n"
    echo -e "    -r|--registry <REGISTRY_DNS>    The FQDN or IP of the registry."
    echo -e "    -u|--user <USER_NAME>           The name of the user to use to authenticate with private registry"
    echo -e "    -p|--password <PASSWORD>        The password of the user."
    echo -e "    -c|--clean                      Upload clean images."
    echo -e "    -d|--download-only              Do not connect or upload to a private registy. Downloady only.\n"
    echo -e "    Options --registry, --user and --password are required if --download-only flag is not provided\n"
}

download_images() {

  local image_list=$1
  local image_download_dir=$2
  local upload_path=$3
  local clean=$4

  docker_images=$(docker images)

  for d in $(echo $image_list); do

    local dd=${d%:*}
    local n=${dd##*/}
    local v=${d#*:}
    local a=${image_download_dir}/${n}_${v}.tar

    [[ -z $clean ]] || \
      echo -e "$docker_images" \
        | awk "/\/$n\s+/{ print \$3 }" \
        | uniq \
        | xargs docker rmi -f

    if [[ -e $a ]]; then
      echo -e "\n*** Loading image $n version $v from download archive..."
      docker load --input $a
    else
      echo -e "\n*** Pulling image from $d..."
      docker pull $d
      docker save --output $a $d
    fi

    if [[ -z $download_only ]]; then
      # Upload docker images to private registry
      #
      # If the private registry is using a self-signed certificate 
      # make sure it is set as an insecure registry at docker startup

      echo -e "\n*** Uploading image $n version $v..."
      docker tag $d ${upload_path}/${n}:${v}
      docker push ${upload_path}/${n}:${v}
    fi
  done
}

download_charts() {

  local chart_list=$1
  local chart_download_dir=$2
  local upload_registry=$3
  local registry_ca_cert_file=$4
  local clean=$5

  for c in $(echo $chart_list); do

    local cc=${c%:*}
    local n=${cc##*/}
    local v=${c#*:}
    local a=${chart_download_dir}/${n}-${v}.tgz

    [[ -z $clean ]] || \
      rm -f $a
    if [[ ! -e $a ]]; then
      echo -e "\n*** Downloading chart $n version $v..."
      helm --destination ${chart_download_dir} fetch $cc --version $v
    fi

    if [[ -z $download_only ]]; then
      echo -e "\n*** Uploading chart $n version $v..."
      helm push \
        --ca-file $registry_ca_cert_file \
        $a $upload_registry
    fi
  done

  helm repo update
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
    -c|--clean)
      clean=1
      ;;
    -d|--download-only)
      download_only=1
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z $download_only \
  && ( -z $registry \
  || -z $user \
  || -z $password ) ]]; then

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

# Login to private registry
if [[ -z $download_only ]]; then
  echo -e "Logging in to private registry '$registry' as user '$user'..."
  docker login --username $user --password $password $registry
fi

# Download and upload docker images

tiller_version=${TILLER_VERSION:-v2.13.0}
alpine_image_version=${ALPINE_IMAGE_VERSION:-3.8}
busybox_image_version=${BUSYBOX_IMAGE_VERSION:-1.30.1 }
concourse_image_version=${CONCOURSE_IMAGE_VERSION:-5.0.0}
postgresql_image_version=${POSTGRESQL_IMAGE_VERSION:-11.2.0}
artifactory_image_version=${ARTIFACTORY_IMAGE_VERSION:-6.8.7}
artifactory_nginx_image_version=${ARTIFACTORY_NGINX_IMAGE_VERSION:-6.8.7}
redis_image_version=${REDIS_IMAGE_VERSION:-5.0.4}
minio_image_version=${MINIO_IMAGE_VERSION:-RELEASE.2019-03-20T22-38-47Z}
halyard_image_version=${HALYARD_IMAGE_VERSION:-1.17.0}

image_download_dir=${script_dir}/.downloads/images
mkdir -p $image_download_dir

download_images \
  "
    gcr.io/kubernetes-helm/tiller:${tiller_version}
    alpine:${alpine_image_version}
    busybox:${busybox_image_version}
    concourse/concourse:${concourse_image_version}
    bitnami/postgresql:${postgresql_image_version}
    bitnami/minideb:latest
    docker.bintray.io/jfrog/artifactory-oss:${artifactory_image_version}
    docker.bintray.io/jfrog/nginx-artifactory-pro:${artifactory_nginx_image_version}
    bitnami/redis:${redis_image_version}
    minio/minio:${minio_image_version}
    gcr.io/spinnaker-marketplace/halyard:${halyard_image_version}
  " \
  "$image_download_dir" \
  "${registry}/releng" \
  "$clean"

# Download and upload helm charts

concourse_chart_version=${CONCOURSE_CHART_VERSION:-5.0.0}
postgresql_chart_version=${POSTGRESQL_CHART_VERSION:-3.15.0}
artifactory_chart_version=${ARTIFACTORY_CHART_VERSION:-7.12.16}
spinnaker_chart_version=${SPINNAKER_CHART_VERSION:-1.8.1}

helm init --client-only >/dev/null 2>&1
helm repo add jfrog https://charts.jfrog.io/
if [[ -z $download_only ]]; then
  helm repo add \
    --ca-file $ca_cert_file --username $user --password $password \
    releng https://${registry}/chartrepo/releng
fi
helm repo update

chart_download_dir=${script_dir}/.downloads/charts
mkdir -p $chart_download_dir

download_charts \
  "
    stable/concourse:${concourse_chart_version}
    stable/postgresql:${postgresql_chart_version}
    jfrog/artifactory:${artifactory_chart_version}
    stable/spinnaker:${spinnaker_chart_version}
  " \
  "$chart_download_dir" \
  "releng" \
  "$ca_cert_file" \
  "$clean"
