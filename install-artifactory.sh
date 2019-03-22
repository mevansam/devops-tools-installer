#!/bin/bash

set +e
echo "$0" | grep "\(/install.sh$\)\|\(/uninstall.sh$\)" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo -e "\nERROR! This script cannot be run stand-alone.\n"
  exit 1
fi
set -e

echo -e "\n###############"
echo -e   "# Artifactory #"
echo -e   "###############\n"

install() {

  # Values to interpolate

  alpine_image_version=${ALPINE_IMAGE_VERSION:-3.8}
  busybox_image_version=${BUSYBOX_IMAGE_VERSION:-1.30.1 }
  artifactory_image_version=${ARTIFACTORY_IMAGE_VERSION:-6.8.7}
  artifactory_nginx_image_version=${ARTIFACTORY_NGINX_IMAGE_VERSION:-6.8.7}
  artifactory_chart_version=${ARTIFACTORY_CHART_VERSION:-7.12.13}

  artifactory_pvc_size=20Gi

  pgsql_instance_name=artifactory-db
  db_user=artifactory
  db_password=artifactory
  db_name=artifactory

  # Artifactory Install Paths

  postgresql_install_config=${install_config}/config/artifactory-db
  mkdir -p ${postgresql_install_config}

  artifactory_config=${script_dir}/config/artifactory
  artifactory_install_config=${install_config}/config/artifactory
  mkdir -p ${artifactory_install_config}

  # Interpolate k8s and helm resource declaration files for postgresql chart

  eval "echo \"$(cat ${postgresql_config}/sc-${iaas}.yml)\"" \
    > ${postgresql_install_config}/sc.yml
  eval "echo \"$(cat ${postgresql_config}/pvc.yml)\"" \
    > ${postgresql_install_config}/pvc.yml
  eval "echo \"$(cat ${postgresql_config}/chart-values.yml)\"" \
    > ${postgresql_install_config}/chart-values.yml

  # Create k8s and helm resources for artifactory postgresql db

  kubectl get storageclass $pgsql_instance_name >/dev/null 2>&1 || \
    kubectl create --filename ${postgresql_install_config}/sc.yml
  kubectl get persistentvolumeclaim $pgsql_instance_name --namespace ${environment} >/dev/null 2>&1 || \
    kubectl create --filename ${postgresql_install_config}/pvc.yml

  if [[ -z `echo -e "$helm_deployments" | awk "/^${pgsql_instance_name}\s+/{ print \$1 }"` ]]; then
    echo -e "Installing postgresql helm chart fot '$pgsql_instance_name'..."
    helm install \
      --values ${postgresql_install_config}/chart-values.yml \
      --name $pgsql_instance_name \
      --namespace $environment \
      --version $postgresql_chart_version \
      releng/postgresql
  else
    echo -e "Upgrading postgresql helm chart for '$pgsql_instance_name'..."
    helm upgrade \
      --values ${postgresql_install_config}/chart-values.yml \
      --version $postgresql_chart_version \
      $pgsql_instance_name releng/postgresql
  fi

  service_info=$(kubectl get service ${pgsql_instance_name}-postgresql --namespace ${environment} | tail -1)
  pgsql_host=$(echo $service_info | awk '{ print $3 }')
  pgsql_port=$(echo $service_info | awk '{ print substr($5,0,index($5,"/")-1) }')

  # Interpolate k8s and helm resource declaration files for artifactory chart

  eval "echo \"$(cat ${artifactory_config}/sc-${iaas}.yml)\"" \
    > ${artifactory_install_config}/sc.yml
  eval "echo \"$(cat ${artifactory_config}/pvc.yml)\"" \
    > ${artifactory_install_config}/pvc.yml
  eval "echo \"$(cat ${artifactory_config}/chart-values.yml)\"" \
    > ${artifactory_install_config}/chart-values.yml

  # Create k8s and helm resources for artifactory

  kubectl get storageclass artifactory >/dev/null 2>&1 || \
    kubectl create --filename ${artifactory_install_config}/sc.yml
  kubectl get persistentvolumeclaim artifactory --namespace ${environment} >/dev/null 2>&1 || \
    kubectl create --filename ${artifactory_install_config}/pvc.yml

  if [[ -z `echo -e "$helm_deployments" | awk '/^artifactory\s+/{ print $1 }'` ]]; then
    echo -e "Installing artifactory helm chart..."
    helm install \
      --values ${artifactory_install_config}/chart-values.yml \
      --name artifactory \
      --namespace $environment \
      --version $artifactory_chart_version \
      releng/artifactory
  else
    echo -e "Upgrading artifactory helm chart..."
    helm upgrade \
      --values ${artifactory_install_config}/chart-values.yml \
      --version $artifactory_chart_version \
      artifactory releng/artifactory
  fi
}

uninstall() {

  set +e

  # Delete k8s and helm resources of artifactory postgresql
  echo -e "\nDeleting artifactory db helm chart..."
  helm delete --purge artifactory-db
  kubectl delete persistentvolumeclaim artifactory-db --namespace $environment
  kubectl delete storageclass artifactory-db

  # Delete k8s and helm resources of artifactory
  echo -e "\nDeleting artifactory helm chart..."
  helm delete --purge artifactory
  kubectl delete persistentvolumeclaim artifactory --namespace $environment
  kubectl delete storageclass artifactory

  set -e
}

case "$1" in
  install)
    install
    exit 0
    ;;
  uninstall)
    uninstall
    exit 0
    ;;
esac

echo "ERROR! Invalid invocation of install script."
exit 1
