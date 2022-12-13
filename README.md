# posti
New post installer for Ubuntu and Fedora based distributions

## Installation

To install `posti` you will need to do the following:

1. Clone the repository

```sh
https://github.com/Tom-HA/posti.git
```

2. Enter the project's directory

```sh
cd posti
```

3. Execute the installer with root privilages

```sh
sudo bash posti.sh
```

## Usage

Please note that this script needs to be executed with root privilages

```sh
Usage: posti.sh <argumant>

    -d      Install docker
    -f      Force oh-my-zsh installation
    -h      Print help
    -H      Install Helm 3
    -t      Configure termianl with zsh extensions
    -T      Configure Tilix
    -z      Configure .zshrc
```