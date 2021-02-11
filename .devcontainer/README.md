# Info on how to use a docker container to do devops development work

## Background Important Links:

* [VSCODE Developing inside of a Container](https://code.visualstudio.com/docs/remote/containers)
* [VSCODE Connect to remote Docker over SSH](https://code.visualstudio.com/docs/containers/ssh)
* [VSCODE Create a Dev Container](https://code.visualstudio.com/docs/remote/create-dev-container)
* [VSCODE Advanced Container Configureation](https://code.visualstudio.com/docs/remote/containers-advanced)

## Setup for using a remote workstation/server/vm for development

1. Install extension "Remote - Container" in vscode
1. Ensure that you have ssh key access setup from your local environment to the remote
1. Install docker on your local environment as it is needed to build the container locally before it provisions it on the remote
1. Install docker on the remote
1. Create a docker context pointing to the remote

```
docker context create remote-docker --docker "host=ssh://user@host.domain.name:22"
```

6. You can validate that the context exists with

```
docker context list
```

7. Open the folder above the .devcontainer in vscode or alternatively you can use the Command Pallette to do a "Remote-Containers: Open Folder in Container..."

## Rebuild the running container with changes to container config

1. Bottom left hand corner click or open Command Pallette and use "Remote-Containers: Rebuild Container"

## AWS credentials

They are stored in a file "devcontainer.env" and not included in git due to a .gitignore restriction. They are in a standard AWS credentials format.
