# DevOps Tools Installer

This repository contains a scripts to deploy a set of common DevOps tools to a Kubernetes cluster. It will optional integrate these tools with [PAS](https://pivotal.io/platform/pivotal-application-service) or [PKS](https://pivotal.io/platform/pivotal-container-service).

## Pre-requisites

1) The following CLIs must be installed and mapped to the system path.
   - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
   - [helm](https://helm.sh/)
   - [uaac](https://github.com/cloudfoundry/cf-uaac) - only required if you plan to integrate with PAS/PKS.

2) The `kubectl` context must be set to the cluster to which the tools should be deployed.

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
USAGE: install.sh -i|--iaas <IAAS_NAME> -e|--environment <ENVIRONMENT> -r|--registry <REGISTRY_DNS>

    This utility will install the 'devops' tools using images and charts uploaded to the
    given private registry. It will also deploy Helm's tiller container to the kubernetes
    cluster if has not been deployed.

    -i|--iaas <IAAS_NAME>           The underlying IAAS for allocating IAAS specific resource such as persistent volumes.
    -e|--environment <ENVIRONMENT>  The namespace environment to deploy relelease engineering services to.
    -r|--registry <REGISTRY_DNS>    The FQDN or IP of the registry.
    -t|--tools <PRODUCT_LIST>       Comma separated list of tools to install or uninstall.
                                    If not provided then all the tools will be deployed.
    -u|--uninstall                  Uninstalls the tool.
```

