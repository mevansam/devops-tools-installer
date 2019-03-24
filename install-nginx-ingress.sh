#!/bin/bash

set +e
echo "$0" | grep "\(/install.sh$\)\|\(/uninstall.sh$\)" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo -e "\nERROR! This script cannot be run stand-alone.\n"
  exit 1
fi
set -e

echo -e "\n############################"
echo -e   "# NGINX Ingress Controller #"
echo -e   "############################\n"

install() {

  # Values to interpolate

  nginx_ingress_controller_version=${NGINX_INGRESS_CONTROLLER_VERSION:-0.23.0}
  defaultbackend_version=${DEFAULTBACKEND_VERSION:-1.4}
  nginx_ingress_chart_version=${NGINX_INGRESS_CHART_VERSION:-1.4.0}

  nginx_ingress_tls_cert=$(cat ${script_dir}/.certs/platform-san.crt | base64)
  nginx_ingress_tls_key=$(cat ${script_dir}/.certs/platform-san.key | base64)

  # NGINX-Ingress Install Paths

  nginx_ingress_config=${script_dir}/config/nginx-ingress
  nginx_ingress_install_config=${install_config}/config/nginx-ingress
  mkdir -p ${nginx_ingress_install_config}

  # Interpolate k8s and helm resource declaration files for nginx_ingress chart

  eval "echo \"$(cat ${nginx_ingress_config}/tls-cert-secret.yml)\"" \
    > ${nginx_ingress_install_config}/tls-cert-secret.yml
  eval "echo \"$(cat ${nginx_ingress_config}/chart-values.yml)\"" \
    > ${nginx_ingress_install_config}/chart-values.yml

  # Create k8s and helm resources for nginx_ingress 

  set +e
  kubectl delete \
    secret nginx-ingress-tls \
    --namespace $environment >/dev/null 2>&1
  set -e
  
  kubectl create \
    --filename .install/config/nginx-ingress/tls-cert-secret.yml

  if [[ -z `echo -e "$helm_deployments" | awk '/^nginx-ingress\s+/{ print $1 }'` ]]; then
    echo -e "Installing nginx-ingress helm chart..."
    helm install \
      --values ${nginx_ingress_install_config}/chart-values.yml \
      --name nginx-ingress \
      --namespace $environment \
      --version $nginx_ingress_chart_version \
      releng/nginx-ingress
  else
    echo -e "Upgrading nginx_ingress helm chart..."
    helm upgrade \
      --values ${nginx_ingress_install_config}/chart-values.yml \
      --version $nginx_ingress_chart_version \
      nginx-ingress releng/nginx-ingress
  fi
}

uninstall() {

  set +e

  # Delete k8s and helm resources of nginx_ingress
  echo -e "\nDeleting nginx-ingress helm chart..."
  helm delete --purge nginx-ingress

  set -e
}

case "$1" in
  install)
    install
    ;;
  uninstall)
    uninstall
    ;;
  *)
    echo "ERROR! Invalid invocation of install script."
    exit 1
esac
