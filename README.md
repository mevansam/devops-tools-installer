# DevOps Tools Installer

This repository contains a scripts to deploy a set of common DevOps tools to a Kubernetes cluster. It will optional integrate these tools with [PAS](https://pivotal.io/platform/pivotal-application-service) or [PKS](https://pivotal.io/platform/pivotal-container-service).

## Pre-requisites

1) The following CLIs must be installed and mapped to the system path.
   - [docker](https://docs.docker.com/install/)
   - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
   - [helm](https://helm.sh/)
   - [uaac](https://github.com/cloudfoundry/cf-uaac) - only required if you plan to integrate with PAS/PKS.

2) If the private registry you plan to use is using a self-signed certificate make sure it is set as an insecure registry on Docker.
   - https://docs.docker.com/registry/insecure/
   - https://github.com/Juniper/contrail-docker/wiki/Configure-docker-service-to-use-insecure-registry

3) The `kubectl` context must be set to the cluster to which the tools should be deployed.

4) The [Helm push plugin](https://github.com/chartmuseum/helm-push) must be installed to push Helm charts to the private registry.

    ```
    helm plugin install https://github.com/chartmuseum/helm-push
    ```

## Tools

### download.sh

```
USAGE: download.sh -r|--registry <REGISTRY_DNS> \
                   -u|--user <USER_NAME> [ -p|--password <PASSWORD> ] [ -c|--clean ]

    This utility will download all required artifacts to set up the devops tools. It will
    upload them to a private registry such as Harbor. Downloaded images and charts will
    be saved locally and re-used for off-line installs.

    -r|--registry <REGISTRY_DNS>    The FQDN or IP of the registry.
    -u|--user <USER_NAME>           The name of the user to use to authenticate with private registry
    -p|--password <PASSWORD>        The password of the user.
    -c|--clean <REGISTRY_DNS>       Upload clean images.
```

### install.sh

```
USAGE: download.sh [ -r|--registry <REGISTRY_DNS> ] \
                   [ -u|--user <USER_NAME> ] [ -p|--password <PASSWORD> ] \
                   [ -c|--clean ] [ -d|--download-only ]

    This utility will download all required artifacts to set up the devops tools. It will
    upload them to a private registry such as Harbor. Downloaded images and charts will
    be saved locally and re-used for off-line installs.

    -r|--registry <REGISTRY_DNS>    The FQDN or IP of the registry.
    -u|--user <USER_NAME>           The name of the user to use to authenticate with private registry
    -p|--password <PASSWORD>        The password of the user.
    -c|--clean                      Upload clean images.
    -d|--download-only              Do not connect or upload to a private registy. Downloady only.

    Options --registry, --user and --password are required if --download-only flag is not provided
```
