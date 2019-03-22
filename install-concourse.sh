#!/bin/bash

set +e
echo "$0" | grep "\(/install.sh$\)\|\(/uninstall.sh$\)" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo -e "\nERROR! This script cannot be run stand-alone.\n"
  exit 1
fi
set -e

echo -e "\n#############"
echo -e   "# Concourse #"
echo -e   "#############\n"

install() {

  # Set up UAA clients for Concourse SSO

  if [[ -n $CONCOURSE_EXTERNAL_URL ]]; then

    if [[ -n $PAS_UAA_URL && -n $PAS_UAA_ADMIN_CLIENT_SECRET ]]; then
      echo -e "\nCreating PAS OAuth client of concourse..."
      create_uaa_client \
        "$PAS_UAA_URL" \
        "$PAS_UAA_ADMIN_CLIENT_SECRET" \
        "openid,email,profile,cloud_controller.read"

      CF_AUTH_ENABLED=true
      CF_API_URL=$(echo "$PAS_UAA_URL" | sed 's|https://uaa\.|https://api.|')
      CF_CLIENT_ID=concourse
      CF_CLIENT_SECRET="$CONCOURSE_CLIENT_SECRET"
    fi

    if [[ -n $PKS_UAA_URL && -n $PKS_UAA_ADMIN_CLIENT_SECRET ]]; then
      echo -e "\nCreating PKS OAuth client of concourse..."
      create_uaa_client \
        "$PKS_UAA_URL" \
        "$PKS_UAA_ADMIN_CLIENT_SECRET" \
        "openid,email,profile"

      OATH_ENABLED=true
      OATH_DISPLAY_NAME="PKS"
      OATH_AUTH_URL=${PKS_UAA_URL}/oauth/authorize
      OATH_TOKEN_URL=${PKS_UAA_URL}/oauth/token
      OATH_USERINFO_URL=${PKS_UAA_URL}/userinfo
      OATH_GROUPS_KEY=groups
      OAUTH_CLIENT_ID=concourse
      OAUTH_CLIENT_SECRET="$CONCOURSE_CLIENT_SECRET"
    fi
  fi

  # Values to interpolate

  concourse_image_version=${CONCOURSE_IMAGE_VERSION:-5.0.0}
  concourse_chart_version=${CONCOURSE_CHART_VERSION:-5.0.0}

  pgsql_instance_name=concourse-db
  db_user=concourse
  db_password=concourse
  db_name=concourse

  concourse_external_url=${CONCOURSE_EXTERNAL_URL:-}
  concourse_local_users=${CONCOURSE_LOCAL_USERS:-"'concourse:P@ssw0rd'"}

  local_user=""
  for u in $(echo $concourse_local_users | sed "s|'||g" | sed 's|,| |'); do 
    local_user="${u%:*},${local_user}"
  done

  cf_auth_enabled=${CF_AUTH_ENABLED:-false}
  cf_api_url=${CF_API_URL:-}
  cf_use_ca_cert=${CF_USE_CA_CERT:-false}
  cf_skip_ssl_validation=${CF_SKIP_SSL_VALIDATION:-true}
  cf_client_id=${CF_CLIENT_ID:-}
  cf_client_secret=${CF_CLIENT_SECRET:-}
  cf_ca_cert=${CF_CA_CERT:-}

  github_auth_enabled=${GITHUB_AUTH_ENABLED:-false}
  github_host=${GITHUB_HOST:-github.com}
  github_cert=${GITHUB_CERT:-false}
  github_client_id=${GITHUB_CLIENT_ID:-}
  github_client_secret=${GITHUB_CLIENT_SECRET:-}
  github_ca_cert=${GITHUB_CA_CERT:-}

  gitlab_auth_enabled=${GITLAB_AUTH_ENABLED:-false}
  gitlab_host=${GITLAB_HOST:-}
  gitlab_client_id=${GITLAB_CLIENT_ID:-}
  gitlab_client_secret=${GITLAB_CLIENT_SECRET:-}

  oath_enabled=${OATH_ENABLED:-false}
  oath_display_name=${OATH_DISPLAY_NAME:-}
  oath_auth_url=${OATH_AUTH_URL:-}
  oath_token_url=${OATH_TOKEN_URL:-}
  oath_userinfo_url=${OATH_USERINFO_URL:-}
  oath_scope=${OATH_SCOPE:-}
  oath_groups_key=${OATH_GROUPS_KEY:-}
  oath_use_ca_cert=${OATH_USE_CA_CERT:-false}
  oath_skip_ssl_validation=${OATH_SKIP_SSL_VALIDATION:-true}
  oauth_client_id=${OAUTH_CLIENT_ID:-}
  oauth_client_secret=${OAUTH_CLIENT_SECRET:-}
  oauth_ca_cert=${OAUTH_CA_CERT:-}

  # Concourse Install Paths

  postgresql_install_config=${install_config}/config/concourse-db
  mkdir -p ${postgresql_install_config}

  concourse_config=${script_dir}/config/concourse
  concourse_install_config=${install_config}/config/concourse
  mkdir -p ${concourse_install_config}

  concourse_web_tls_cert=$(cat ${script_dir}/.certs/concourse-ci.crt | sed "s|\(.*\)$|    \1|g")
  concourse_web_tls_key=$(cat ${script_dir}/.certs/concourse-ci.key | sed "s|\(.*\)$|    \1|g")

  # Interpolate k8s and helm resource declaration files for postgresql chart

  eval "echo \"$(cat ${postgresql_config}/sc-${iaas}.yml)\"" \
    > ${postgresql_install_config}/sc.yml
  eval "echo \"$(cat ${postgresql_config}/pvc.yml)\"" \
    > ${postgresql_install_config}/pvc.yml
  eval "echo \"$(cat ${postgresql_config}/chart-values.yml)\"" \
    > ${postgresql_install_config}/chart-values.yml

  # Create k8s and helm resources for concourse postgresql db

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

  # Interpolate k8s and helm resource declaration files for concourse chart

  eval "echo \"$(cat ${concourse_config}/sc-${iaas}.yml)\"" \
    > ${concourse_install_config}/sc.yml
  eval "echo \"$(cat ${concourse_config}/chart-values.yml)\"" \
    > ${concourse_install_config}/chart-values.yml

  # Create k8s and helm resources for concourse

  kubectl get storageclass concourse-ci >/dev/null 2>&1 || \
    kubectl create --filename ${concourse_install_config}/sc.yml

  if [[ -z `echo -e "$helm_deployments" | awk '/^concourse-ci\s+/{ print $1 }'` ]]; then
    echo -e "Installing concourse helm chart..."
    helm install \
      --values ${concourse_install_config}/chart-values.yml \
      --name concourse-ci \
      --namespace $environment \
      --version $concourse_chart_version \
      releng/concourse
  else
    echo -e "Upgrading concourse helm chart..."
    helm upgrade \
      --values ${concourse_install_config}/chart-values.yml \
      --version $concourse_chart_version \
      concourse-ci releng/concourse
  fi
}

uninstall() {

  set +e

  # Delete k8s and helm resources of concourse postgresql
  echo -e "\nDeleting concourse db helm chart..."
  helm delete --purge concourse-db
  kubectl delete persistentvolumeclaim concourse-db --namespace $environment
  kubectl delete storageclass concourse-db

  # Delete k8s and helm resources of concourse chart
  echo -e "\nDeleting concourse ci helm chart..."
  helm delete --purge concourse-ci
  kubectl delete namespace concourse-ci-main
  kubectl delete storageclass concourse-ci

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
