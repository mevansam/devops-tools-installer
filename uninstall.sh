#!/bin/bash

script_dir=$(cd $(dirname $0) && pwd)

usage () {
    echo -e "\nUSAGE: uninstall.sh -e|--environment <ENVIRONMENT>\n"
    echo -e "This utility will uninstall all 'releng' Helm deploymnets.\n"
    echo -e "    -e|--environment <ENVIRONMENT>  The namespace environment to deploy relelease engineering services to."
    echo -e ""
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
    -e|--environment)
      environment=$2
      shift
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z $environment ]]; then
  usage
  exit 1
fi

# Uninstall Concourse Helm chart
# source ${script_dir}/install-concourse.sh uninstall

# Uninstall Artifactory Helm chart
source ${script_dir}/install-artifactory.sh uninstall
