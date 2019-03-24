#!/bin/bash

set +e
echo "$0" | grep "\(/install.sh$\)\|\(/uninstall.sh$\)" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo -e "\nERROR! This script cannot be run stand-alone.\n"
  exit 1
fi
set -e

echo -e "\n#############"
echo -e   "# Spinnaker #"
echo -e   "#############\n"

install() {

  # Values to interpolate

  halyard_image_version=${HALYARD_IMAGE_VERSION:-1.17.0}
  spinnaker_chart_version=${SPINNAKER_CHART_VERSION:-1.8.1}

  redis_instance_name=spinnaker-redis-store
  redis_pvc_size=${REDIS_PVC_SIZE:-8Gi}
  redis_password=i8Us38W4YZ

  minio_instance_name=spinnaker-minio-store
  minio_pvc_size=${MINIO_PVC_SIZE:-10Gi}

  minio_access_key=6c5923MmK4
  minio_secret_key=VrphtZmm5m6LRT5xfeCkzavz

  spinnaker_app_version=${SPINNAKER_APP_VERSION:-1.12.5}

  upload_kubeconfig=${UPLOAD_KUBECONFIG:-false}
  spinnakker_target_contexts=${SPINNAKKER_TARGET_CONTEXTS:-[]}
  spinnaker_deployment_context=$(kubectl config current-context)

  # Install Paths

  redis_install_config=${install_config}/config/spinnaker_redis
  mkdir -p ${redis_install_config}

  minio_install_config=${install_config}/config/spinnaker_minio
  mkdir -p ${minio_install_config}

  spinnaker_config=${script_dir}/config/spinnaker
  spinnaker_install_config=${install_config}/config/spinnaker
  mkdir -p ${spinnaker_install_config}

  # Interpolate k8s and helm resource declaration files for redis chart

  eval "echo \"$(cat ${redis_config}/sc-${iaas}.yml)\"" \
    > ${redis_install_config}/sc.yml
  eval "echo \"$(cat ${redis_config}/pvc.yml)\"" \
    > ${redis_install_config}/pvc.yml
  eval "echo \"$(cat ${redis_config}/chart-values.yml)\"" \
    > ${redis_install_config}/chart-values.yml

  # Create k8s and helm resources for spinnaker redis

  kubectl get storageclass $redis_instance_name >/dev/null 2>&1 || \
    kubectl create --filename ${redis_install_config}/sc.yml
  kubectl get persistentvolumeclaim $redis_instance_name --namespace ${environment} >/dev/null 2>&1 || \
    kubectl create --filename ${redis_install_config}/pvc.yml

  if [[ -z `echo -e "$helm_deployments" | awk "/^${redis_instance_name}\s+/{ print \$1 }"` ]]; then
    echo -e "Installing redis helm chart for '$redis_instance_name'..."
    helm install \
      --values ${redis_install_config}/chart-values.yml \
      --name $redis_instance_name \
      --namespace $environment \
      --version $redis_chart_version \
      releng/redis
  else
    echo -e "Upgrading redis helm chart for '$redis_instance_name'..."
    helm upgrade \
      --values ${redis_install_config}/chart-values.yml \
      --version $redis_chart_version \
      $redis_instance_name releng/redis
  fi

  service_info=$(kubectl get service ${redis_instance_name}-master --namespace ${environment} | tail -1)
  redis_host=$(echo $service_info | awk '{ print $3 }')
  redis_port=$(echo $service_info | awk '{ print substr($5,0,index($5,"/")-1) }')

  # Interpolate k8s and helm resource declaration files for minio chart

  eval "echo \"$(cat ${minio_config}/sc-${iaas}.yml)\"" \
    > ${minio_install_config}/sc.yml
  eval "echo \"$(cat ${minio_config}/pvc.yml)\"" \
    > ${minio_install_config}/pvc.yml
  eval "echo \"$(cat ${minio_config}/chart-values.yml)\"" \
    > ${minio_install_config}/chart-values.yml  

  # Create k8s and helm resources for spinnaker minio

  kubectl get storageclass $minio_instance_name >/dev/null 2>&1 || \
    kubectl create --filename ${minio_install_config}/sc.yml
  kubectl get persistentvolumeclaim $minio_instance_name --namespace ${environment} >/dev/null 2>&1 || \
    kubectl create --filename ${minio_install_config}/pvc.yml

  if [[ -z `echo -e "$helm_deployments" | awk "/^${minio_instance_name}\s+/{ print \$1 }"` ]]; then
    echo -e "Installing minio helm chart for '$minio_instance_name'..."
    helm install \
      --values ${minio_install_config}/chart-values.yml \
      --name $minio_instance_name \
      --namespace $environment \
      --version $minio_chart_version \
      releng/minio
  else
    echo -e "Upgrading minio helm chart for '$minio_instance_name'..."
    helm upgrade \
      --values ${minio_install_config}/chart-values.yml \
      --version $minio_chart_version \
      $minio_instance_name releng/minio
  fi

  service_info=$(kubectl get service ${minio_instance_name} --namespace ${environment} | tail -1)
  minio_host=$(echo $service_info | awk '{ print $3 }')
  minio_port=$(echo $service_info | awk '{ print substr($5,0,index($5,"/")-1) }')

  # Interpolate k8s and helm resource declaration files for spinnaker chart

  eval "echo \"$(cat ${spinnaker_config}/chart-values.yml)\"" \
    > ${spinnaker_install_config}/chart-values.yml

  # Create k8s and helm resources for spinnaker spinnaker

  set +e
  kubectl delete \
    secret spinnaker-kubeconfig \
    --namespace $environment >/dev/null 2>&1
  set -e
  
  kubectl create \
    secret generic \
    --namespace $environment \
    --from-file=$HOME/.kube/config spinnaker-kubeconfig

  if [[ -z `echo -e "$helm_deployments" | awk "/^spinnaker\s+/{ print \$1 }"` ]]; then
    echo -e "Installing spinnaker helm chart for 'spinnaker'..."
    helm install \
      --values ${spinnaker_install_config}/chart-values.yml \
      --name spinnaker \
      --namespace $environment \
      --version $spinnaker_chart_version \
      releng/spinnaker
  else
    echo -e "Upgrading spinnaker helm chart for 'spinnaker'..."
    helm upgrade \
      --values ${spinnaker_install_config}/chart-values.yml \
      --version $spinnaker_chart_version \
      spinnaker releng/spinnaker
  fi
}

uninstall() {

  set +e

  # Delete k8s and helm resources of spinnaker redis
  echo -e "\nDeleting spinnaker helm chart..."
  helm delete --purge spinnaker
  kubectl delete job spinnaker-install-using-hal --namespace $environment
  kubectl delete job spinnaker-spinnaker-cleanup-using-hal --namespace $environment

  # Delete k8s and helm resources of spinnaker redis
  echo -e "\nDeleting spinnaker redis helm chart..."
  helm delete --purge spinnaker-redis-store
  kubectl delete persistentvolumeclaim spinnaker-redis-store --namespace $environment
  kubectl delete storageclass spinnaker-redis-store

  # Delete k8s and helm resources of spinnaker redis
  echo -e "\nDeleting spinnaker minio helm chart..."
  helm delete --purge spinnaker-minio-store
  kubectl delete persistentvolumeclaim spinnaker-minio-store --namespace $environment
  kubectl delete storageclass spinnaker-minio-store

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
