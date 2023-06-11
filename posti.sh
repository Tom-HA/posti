#!/usr/bin/env bash

main() {
    set_variables
    handle_flags "$@"
    update_and_upgrade
    curl_installation
    code_installation
    packages_installation

    if [[ ${pkg_manager} == "brew" ]]; then
        echo_green "Installation completed"
        exit 0
    fi

    install_fonts
    configre_vscode_fonts
    configure_terminal
    configure_zshrc
    configure_tilix
    docker_installation
    kubectl_installation
    # minikube_installation
    helm_installation
    
    echo_green "Installation completed"
    exit 0
}

check_root_and_exit() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be executed with root privileges"
        exit 1
    fi
}

set_variables() {
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    yellow=$(tput setaf 3)
    reset=$(tput sgr0)
    log="/tmp/posti.log"
    SUDO_USER=${SUDO_USER:=$USER}
    home_dir_path=$(grep ${SUDO_USER} /etc/passwd |awk -F ':' '{print $6}')
    home_dir_path=${home_dir_path:=$HOME}

    # $r equals to $0 without '/' if exists and the script name suffix 
    r=$(sed -E "s|/?${0##*/}||" <<< $0)
    relative_path=${r:=.}
}

echo_white() {
    echo "$*" |tee -a ${log}
}

echo_red() {
    echo -e "${red}$*${reset}\n${yellow}Log file available at: ${log}${reset}" |tee -a ${log}
}

echo_yellow() {
    echo "${yellow}$*${reset}" |tee -a ${log}
}

echo_green() {
    echo "${green}$*${reset}" |tee -a ${log}
}

progress_spinner () {

    ## Loop until the PID of the last background process is not found
    while ps aux |awk '{print $2}' |grep -E -o "$BPID" &> /dev/null; do
        # Print text with a spinner
        printf "\r%s in progress...  ${yellow}[|]${reset}" "$*"
        sleep 0.1
        printf "\r%s in progress...  ${yellow}[/]${reset}" "$*"
	sleep 0.1
	printf "\r%s in progress...  ${yellow}[-]${reset}" "$*"
	sleep 0.1
	printf "\r%s in progress...  ${yellow}[\\]${reset}" "$*"
	sleep 0.1
	printf "\r%s in progress...  ${yellow}[|]${reset}" "$*"
    done

    # Print a new line outside the loop so it will not interrupt with the it
    # and will not interrupt with the upcoming text of the script
    printf "\n\n"
}

set_package_manager() {
    if command -v apt-get &> /dev/null; then
        pkg_manager="apt-get"
        pkg_manager_args=("install" "-y")
        echo_white "Detected package manager: apt"
    
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
        pkg_manager_args=("install" "-y")
        echo_white "Detected package manager: dnf"

    elif command -v brew &> /dev/null; then
        pkg_manager="brew"
        pkg_manager_args=("install" "-y")
        echo_white "Detected package manager: brew"


    elif command -v yay &> /dev/null; then
        pkg_manager="yay"
        pkg_manager_args=("-S" "--noconfirm")
        read -sp "Please enter [sudo] password: " sudo_pass
        if ! runuser -l ${SUDO_USER} -c "sudo -S echo test &> /dev/null <<< $(echo ${sudo_pass})"; then
            echo_red "Bad password"
            exit 1
        fi
	    echo_white "Detected package manager: yay"

    else
        echo_red "Could not detect package manager"
        exit 1
    fi
}

send_to_spinner() {

    if [[ -z ${1} ]] || [[ -z ${2} ]]; then
        echo_red "Function 'send_to_spinner' didn't receive sufficient arguments"
    fi
    bash -c "${1}" &>> ${log} &
    BPID=$!
    progress_spinner "${2}"
    wait ${BPID}
    status=$?
    if [[ ${status} -ne 0 ]]; then
        echo_red "Failed to perform ${1}"
        exit 1
    fi
}

update_and_upgrade(){
    echo_white "Updating the system"

    if [[ ${pkg_manager} == "apt-get" ]]; then
        send_to_spinner "apt-get update" "System update"
        send_to_spinner "apt-get upgrade -y" "System upgrade"

    elif [[ ${pkg_manager} == "dnf" ]]; then
        send_to_spinner "dnf update -y" "System upgrade"

    elif [[ ${pkg_manager} == "yay" ]]; then
        send_to_spinner "pacman -Syu --noconfirm" "System upgrade"
    fi
}

curl_installation() { 
    if ! command -v curl &> /dev/null; then
        send_to_spinner "${pkg_manager} ${pkg_manager_args[*]} curl" "curl installation"
    fi
}

packages_installation() {
    echo_white "Installing packages"
    generic_pkgs=(git zsh ncdu tilix screenfetch virtualbox copyq)
    ubuntu_pkgs=(ssh virtualbox-ext-pack)
    arch_pkgs=(openssh firefox vlc discord docker)

    for pkg in "${generic_pkgs[@]}"; do
        if command -v ${pkg} &> /dev/null; then
            continue
        fi
        send_to_spinner "${pkg_manager} ${pkg_manager_args[*]} ${pkg}" "${pkg} installation"
    done

    if [[ ${pkg_manager} == "apt-get" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        echo virtualbox-ext-pack virtualbox-ext-pack/license select true | debconf-set-selections 
        send_to_spinner "add-apt-repository multiverse" "Adding multiverse repo"
        send_to_spinner "add-apt-repository ppa:hluk/copyq" "Adding copyq repo"
        send_to_spinner "apt-get update" "System update"

        for pkg in "${ubuntu_pkgs[@]}"; do
            if command -v ${pkg} &> /dev/null; then
                continue
            fi
            send_to_spinner "${pkg_manager} ${pkg_manager_args[*]} ${pkg}" "${pkg} installation"
        done

    elif [[ ${pkg_manager} == "yay" ]]; then
        for pkg in "${arch_pkgs[@]}"; do
            if command -v ${pkg} &> /dev/null; then
                continue
            fi
            send_to_spinner "${pkg_manager} ${pkg_manager_args[*]} ${pkg}" "${pkg} installation"
        done
	    send_to_spinner "runuser -l ${SUDO_USER} -c '${pkg_manager} ${pkg_manager_args[*]} --sudoflags -S virtualbox-ext-oracle <<<$(echo ${sudo_pass})'" "Installing virtualbox-ext-oracle"

    fi

    echo_green "Packages installtion finished successfully"
}

code_installation() {
    if command -v code &> /dev/null; then
        return 0
    fi

    echo_white "Installing Visual Studio Code"
    if [[ ${pkg_manager} == "apt-get" ]]; then
        snap_installation
        send_to_spinner "snap install --classic code" "Visual Studio Code installation"
        ln -sf /snap/vscode /snap/code
        return 0
    
    elif [[ ${pkg_manager} == "dnf" ]]; then
        echo_yellow "Visual Studio code installation is not supported for 'dnf' package manager"
        return 0
    
    elif [[ ${pkg_manager} == "brew" ]]; then
        echo_yellow "Visual Studio code installation is not supported for 'brew' package manager"
        return 0
    elif [[ ${pkg_manager} == "yay" ]]; then
	    send_to_spinner "runuser -l ${SUDO_USER} -c '${pkg_manager} ${pkg_manager_args[*]} --sudoflags -S visual-studio-code-bin <<<$(echo ${sudo_pass})'" "Installing Visual Studio Code"
    fi


    # curl h -L --silent https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    # install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/ &>> ${log}
    # echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list
    # send_to_spinner "apt-get update" "System update"
    # send_to_spinner "apt-get install -y code" "Installing Visual Studio Code"
    
    echo_green "Visual Studio Code installation finished successfully"
}

snap_installation() {
    if command -v snap &> /dev/null; then
        echo_white "Snap already installed"
	return 0
    fi

    echo_white "Installing snap"
    send_to_spinner "${pkg_manager} install -y snap" "snap installation"
    echo_green "Snap installation finished successfully"
}

docker_installation() {
    if [[ ${pkg_manager} == "yay" ]]; then
        return 0
    fi
    echo_white "Installing docker"
    curl --silent -L -o docker_installation.sh https://get.docker.com
    send_to_spinner "sh docker_installation.sh" "Docker installation"
    usermod -aG docker ${SUDO_USER}
    mv ${relative_path}/docker_installation.sh tmp/ &>> ${log}
    echo_green "Docker installation finished successfully"
}

kubectl_installation() {
    if command -v kubectl &> /dev/null; then
        return 0
    fi

    echo_white "Installing kubectl"
    curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" &>> ${log}
    if ! [[ -s ./kubectl ]]; then
        echo_red "Failed to download kubectl"
        exit 1
    fi

    chmod 755 kubectl
    mv kubectl /usr/local/bin
    echo_green "kubectl installation finished successfully"
}

configure_terminal() {

    if ! command -v zsh &> /dev/null; then
        send_to_spinner "${pkg_manager} ${pkg_manager_args[*]} zsh" "zsh installation"
    fi

    if [[ -d ${home_dir_path}/.oh-my-zsh ]] && [[ ${FORCE} == true ]]; then
        rm -rf ${home_dir_path}/.oh-my-zsh
    elif [[ -d ${home_dir_path}/.oh-my-zsh ]] && [[ ${FORCE} != true ]]; then
        echo_yellow "Directory .oh-my-zsh already exists, use -f to overwrite the configuration"
        return 0
    fi
    if [[ ${pkg_manager} != "brew" ]]; then
        usermod -s /usr/bin/zsh ${SUDO_USER} &>> ${log}
    fi
    curl --silent -L -o ohmyzsh.sh https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
    if [[ ${pkg_manager} != "brew" ]]; then
        chown ${SUDO_USER}:${SUDO_USER} ohmyzsh.sh
    fi
    chmod 755 ohmyzsh.sh
    send_to_spinner "su ${SUDO_USER} -c ./ohmyzsh.sh" "Oh My Zsh installation"
    send_to_spinner "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:=${home_dir_path}/.oh-my-zsh/custom}/themes/powerlevel10k" "powerlevel10k installation"
    send_to_spinner "git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:=${home_dir_path}/.oh-my-zsh/custom}/plugins/zsh-completions" "zsh-completions installation" 
    send_to_spinner "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:=${home_dir_path}/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" "zsh-syntax-highlighting installation"
    send_to_spinner "git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:=${home_dir_path}/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" "zsh-autosuggestions installation"

    echo_green "Terminal configured"

}

configure_zshrc() {
    echo_white "Configuring zshrc"
    if [[ -s ${home_dir_path}/.zshrc ]]; then
        if ! [[ -f ${home_dir_path}/.zshrc.bck ]]; then
            cp ${home_dir_path}/.zshrc ${home_dir_path}/.zshrc.bck
        fi
    fi

    if [[ ${pkg_manager} == "brew" ]]; then
        sed -i.bck "s|^ZSH_THEME=.*|ZSH_THEME=powerlevel10k/powerlevel10k|" ${home_dir_path}/.zshrc
        sed -i.bck "s|^plugins=.*|plugins=(git aws kubectl zsh-completions zsh-syntax-highlighting zsh-autosuggestions)|" ${home_dir_path}/.zshrc
    else
        sed -i "s|^ZSH_THEME=.*|ZSH_THEME=powerlevel10k/powerlevel10k|" ${home_dir_path}/.zshrc
        sed -i "s|^plugins=.*|plugins=(git aws kubectl zsh-completions zsh-syntax-highlighting zsh-autosuggestions)|" ${home_dir_path}/.zshrc
    fi

    if ! grep -q "alias k=" ${home_dir_path}/.zshrc; then
        echo 'alias k="kubectl"' >> ${home_dir_path}/.zshrc
    fi

    if ! grep -q "alias d=" ${home_dir_path}/.zshrc; then
        echo 'alias d="docker"' >> ${home_dir_path}/.zshrc
    fi

    if ! grep -q "alias dc=" ${home_dir_path}/.zshrc; then
        echo 'alias dc="docker compose"' >> ${home_dir_path}/.zshrc
    fi

    if ! grep -q "alias t=" ${home_dir_path}/.zshrc; then
        echo 'alias t="terraform"' >> ${home_dir_path}/.zshrc
    fi

    if command -v screenfetch &> /dev/null; then
        if ! grep -q "screenfetch -E" ${home_dir_path}/.zshrc; then
            echo "screenfetch -E" >> ${home_dir_path}/.zshrc
        fi
    fi
    
}

configure_tilix() {

    if ! command -v tilix &> /dev/null; then
        return 0
    fi
    
    if ! command -v dconf &> /dev/null; then
        send_to_spinner "${pkg_manager} ${pkg_manager_args[*]} dconf-cli" "dconf-cli installation"
    fi

    # su ${SUDO_USER} -c "gsettings set org.gnome.desktop.default-applications.terminal exec tilix"
    if command -v update-alternatives &> /dev/null; then
        tilix_alternative="$(update-alternatives --list x-terminal-emulator |grep tilix)"

        echo_white "Setting Tilix as the default terminal"
        if ! update-alternatives --set x-terminal-emulator ${tilix_alternative:?} &>> ${log}; then
            echo_red "could not set Tilix as the default terminal"
            exit 1
        fi
    fi

    if ! [[ -s ${relative_path}/config/tilix.dconf ]]; then
        echo_red "could not detect tilix.dconf, try to clone the repository again"
        exit 1
    fi
    export tlilx_dconf_full_path="$(readlink -f ${relative_path}/config/tilix.dconf)"
    runuser -l ${SUDO_USER} -c "exec dbus-run-session -- bash -c 'dconf load /com/gexperts/Tilix/ < ${tlilx_dconf_full_path}'" &>> ${log}

    if ! grep -q 'source /etc/profile.d/vte.sh' ${home_dir_path}/.zshrc; then
        printf '
# Tilix
if [ $TILIX_ID ] || [ $VTE_VERSION ]; then
    source /etc/profile.d/vte.sh
fi
' >> ${home_dir_path}/.zshrc
    fi
    echo_green "Tilix configured"
}

install_fonts() {

    if ! [[ -d /usr/share/fonts/'Droid Sans Mono' ]]; then
        mkdir -p /usr/share/fonts/'Droid Sans Mono' &>> ${log}
    fi 
    send_to_spinner "curl -f -s -L https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/DroidSansMono/complete/Droid%20Sans%20Mono%20Nerd%20Font%20Complete%20Mono.otf -o /usr/share/fonts/Droid\ Sans\ Mono/Droid\ Sans\ Mono\ for\ Powerline\ Nerd\ Font\ Complete.otf" "Droid Sans Mono font installation"

    if ! [[ -d /usr/share/fonts/MesloLGS ]]; then
        mkdir -p /usr/share/fonts/MesloLGS &>> ${log}
    fi 
    send_to_spinner "curl -f -s -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf -o /usr/share/fonts/MesloLGS/MesloLGS\ NF\ Regular.ttf" "MesloLGS NF Regular font installation"

    echo_green "Font installtion finished successfully"
}

configre_vscode_fonts() {
    echo_white "Configuring VScode fonts"

    if ! command -v code &> /dev/null; then
        return 0
    fi 

    if ! [[ -d ${home_dir_path}/.config/Code/User ]]; then
	    mkdir -p ${home_dir_path}/.config/Code/User
    fi
    printf '{
    "terminal.integrated.fontFamily": "MesloLGS NF Regular",
    "editor.fontFamily": "MesloLGS NF Regular, monospace, monospace",
    "editor.fontLigatures": false,
    "terminal.integrated.defaultProfile.linux": "zsh"
}' > ${home_dir_path}/.config/Code/User/settings.json
    chown -R ${SUDO_USER} ${home_dir_path}/.config/Code

}

minikube_installation() {

    send_to_spinner "curl --silent -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl" "Kubectl installation"
    chmod +x kubectl
    mv kubectl /usr/local/bin/kubectl

    send_to_spinner "curl --silent -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64" "Minikube installation"
    chmod +x minikube
    mv minikube /usr/local/bin/minikube

    echo_green "Minikube installation finished successfully"
}

helm_installation() {
    curl -L --silent https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 -o get-helm-3
    send_to_spinner "bash get-helm-3" "Helm 3 installation"
    mv ${relative_path}/get-helm-3 /tmp/ &>> ${log}
    echo_green "Helm installation finished successfully"
}

print_help() {
    printf "
Usage: ${0##*/} <argumant>

    -d      Install docker
    -f      Force oh-my-zsh installation
    -h      Print help
    -H      Install Helm 3
    -t      Configure termianl with zsh extensions
    -T      Configure Tilix
    -z      Configure .zshrc
    \n"
    
}

handle_flags() {
    while getopts ":hdfHtTz" o; do
        case "${o}" in
            d)
                if [[ ${pkg_manager} == "brew" ]]; then
                    echo_yellow "This operation is not supported with brew"
                    exit 0
                fi
                set_package_manager
                curl_installation
                docker_installation
                ;;
            h)
                print_help
                exit 0
                ;;
            f)
                FORCE="true"
                ;;

            t)
                TERMINAL_CONFIG=true
                ;;
            
            T)
                TILIX_CONFIG=true
                ;;
            H)
                if [[ ${pkg_manager} == "brew" ]]; then
                    echo_yellow "This operation is not supported with brew"
                    exit 0
                fi

                set_package_manager
                curl_installation
                helm_installation
                exit 0
                ;;
            z)
                set_package_manager
                configure_zshrc
                exit 0
                ;;
            *)
                echo_yellow "Invalid argument"
                print_help
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))

    check_root_and_exit
    set_package_manager

    if [[ ${TILIX_CONFIG} == true ]]; then
        
        curl_installation
        install_fonts
        configre_vscode_fonts
        configure_terminal
        configure_zshrc
        configure_tilix
	    exit 0
    fi

    if [[ ${TERMINAL_CONFIG} == true ]]; then
        configure_terminal
        configure_zshrc
        exit 0
    fi

}


main "$@"
