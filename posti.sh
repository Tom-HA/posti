#!/usr/bin/env bash

main() {
    check_root_and_exit
    set_variables
    set_package_manager
    handle_flags "$@"
    update_and_upgrade
    curl_installation
    code_installation
    packages_installation
    install_fonts
    configure_terminal
    configure_tilix
    docker_installation
    minikube_installation
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
        echo_white "Detected package manager: apt"
    
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
        echo_white "Detected package manager: dnf"

    else
        echo_red "Could not detect package manager"
        exit 1
    fi
}

send_to_spinner() {

    if [[ -z ${1} ]] || [[ -z ${2} ]]; then
        echo_red "Function 'send_to_spinner' didn't receive sufficient arguments"
    fi
    ${1} &>> ${log} &
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
    fi
}

curl_installation() {
    if ! command -v curl &> /dev/null; then
        send_to_spinner "${pkg_manager} install -y curl" "curl installation"
    fi
}

packages_installation() {
    echo_white "Installing packages"
    pkg_array=(git zsh plank ssh tilix screenfetch virtualbox virtualbox-ext-pack)
    if [[ ${pkg_manager} == "apt-get" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        echo virtualbox-ext-pack virtualbox-ext-pack/license select true | debconf-set-selections 
    fi
    send_to_spinner "add-apt-repository multiverse" "Adding multiverse repo"
    send_to_spinner "apt-get update" "System update"
    for pkg in "${pkg_array[@]}"; do
        send_to_spinner "${pkg_manager} install -y ${pkg}" "${pkg} installation"
    done

    echo_green "Packages installtion finished successfully"
}

code_installation() {
    echo_white "Installing Visual Studio Code"
    if [[ ${pkg_manager} == "apt-get" ]]; then
        snap_installation
        send_to_spinner "snap install --classic code" "Visual Studio Code installation"
	ln -sf /snap/vscode /snap/code
	return 0
    fi

    curl h -L --silent https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/ &>> ${log}
    echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list
    send_to_spinner "apt-get update" "System update"
    send_to_spinner "apt-get install -y code" "Installing Visual Studio Code"

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
    echo_white "Installing docker"
    curl --silent -L -o docker_installation.sh https://get.docker.com
    send_to_spinner "sh docker_installation.sh" "Docker installation"
    usermod -aG docker ${SUDO_USER}
    mv ${relative_path}/docker_installation.sh tmp/ &>> ${log}
    echo_green "Docker installation finished successfully"
}

configure_terminal() {

    if ! command -v zsh &> /dev/null; then
        send_to_spinner "${pkg_manager} install -y zsh" "zsh installation"
    fi

    if [[ -d ${home_dir_path}/.oh-my-zsh ]] && [[ ${FORCE} == true ]]; then
        rm -rf ${home_dir_path}/.oh-my-zsh
    elif [[ -d ${home_dir_path}/.oh-my-zsh ]] && [[ ${FORCE} != true ]]; then
        echo_yellow "Directory .oh-my-zsh already exists, use -f to overwrite it. Aborting installation"
        exit 1
    fi

    usermod -s /usr/bin/zsh ${SUDO_USER} &>> ${log}
    curl --silent -L -o ohmyzsh.sh https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
    chown ${SUDO_USER}:${SUDO_USER} ohmyzsh.sh
    chmod 755 ohmyzsh.sh
    send_to_spinner "su ${SUDO_USER} -c ./ohmyzsh.sh" "Oh My Zsh installation"
    send_to_spinner "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:=${home_dir_path}/.oh-my-zsh/custom}/themes/powerlevel10k" "powerlevel10k installation"
    send_to_spinner "git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:=${home_dir_path}/.oh-my-zsh/custom}/plugins/zsh-completions" "zsh-completions installation" 
    send_to_spinner "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:=${home_dir_path}/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" "zsh-syntax-highlighting installation"
    send_to_spinner "git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:=${home_dir_path}/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" "zsh-autosuggestions installation"
    if ! [[ -s ${relative_path}/config/zshrc ]]; then
        echo_red "Failed to find custom zshrc"
        exit 1
    fi

    if [[ -s ${home_dir_path}/.zshrc ]]; then
        mv ${home_dir_path}/.zshrc ${home_dir_path}/.zshrc.bck
    fi

    cp -f ${relative_path}/config/zshrc ${home_dir_path}/.zshrc
    sed -i "s|%HOME_USER%|${home_dir_path}|" ${home_dir_path}/.zshrc

    if command -v screenfetch &> /dev/null; then
        echo "screenfetch -E" >> ${home_dir_path}/.zshrc
    fi

    chown -R ${SUDO_USER}:${SUDO_USER} ${home_dir_path}/.zshrc ${home_dir_path}/.zshrc.bck ${ZSH_CUSTOM:=${home_dir_path}/.oh-my-zsh} &>> ${log}

    echo_green "Terminal configured"

}

configure_tilix() {

    if ! command -v tilix &> /dev/null; then
        return 0
    fi
    
    if ! command -v dconf &> /dev/null; then
        send_to_spinner "${pkg_manager} install -y dconf-cli" "dconf-cli installation"
    fi

    su ${SUDO_USER} -c "gsettings set org.gnome.desktop.default-applications.terminal exec tilix"

    if ! [[ -s ${relative_path}/config/tilix.dconf ]]; then
        echo_red "could not detect tilix.dconf, try to clone the repository again"
        exit 1
    fi

    su ${SUDO_USER} -c "dconf load /com/gexperts/Tilix/ < ${relative_path}/config/tilix.dconf"
exit
    if ! grep -q 'source /etc/profile.d/vte.sh' ${home_dir_path}/.zshrc; then
        printf '
# Tilix
if [ $TILIX_ID ] || [ $VTE_VERSION ]; then
    source /etc/profile.d/vte.sh
fi
' >> ${home_dir_path}/.zshrc
    fi
exit
    echo_green "Tilix configured"
}

install_fonts() {

    if ! [[ -d /usr/share/fonts/'Droid Sans Mono' ]]; then
        mkdir -p /usr/share/fonts/'Droid Sans Mono' &>> ${log}
    fi 

    
    send_to_spinner "curl -f -L --silent -o /usr/share/fonts/'Droid Sans Mono'/'Droid Sans Mono for Powerline Nerd Font Complete.otf' https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/DroidSansMono/complete/Droid%20Sans%20Mono%20Nerd%20Font%20Complete.otf" "Droid Sans Mono font installation"
   exit 
    # https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf -O /usr/share/fonts/MesloLGS/'MesloLGS NF Regular.ttf'" "MesloLGS NF Regular font installation"
    if command -v code &> /dev/null; then
        if ! [[ -d ${home_dir_path}/.config/Code/User ]]; then
	    mkdir -p ${home_dir_path}/.config/Code/User
	fi 
        printf '{\n"terminal.integrated.fontFamily": "Droid Sans Mono"\n}\n' > ${home_dir_path}/.config/Code/User/settings.json
    fi

    echo_green "Font installtion finished successfully"
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
    -H      Install helm 3
    -m      Install minikube
    -t      Configure terminal
    \n"
    
}

handle_flags() {

    flags=($@)
    if [[ -z ${flags[@]} ]]; then
        return 0
    fi

    for flag in ${flags[@]}; do 
        if [[ ${flag} =~ ^-h$ ]]; then
            print_help
	    exit 0
        
        elif [[ ${flag} =~ ^-d$ ]]; then
            curl_installation
            docker_installation
	    exit 0

        elif [[ ${flag} =~ ^-f$ ]]; then
            FORCE="true"
            
        elif [[ ${flag} =~ ^-m$ ]]; then 
            curl_installation
            minikube_installation
            exit 0

        elif [[ ${flag} =~ ^-H$ ]]; then
            curl_installation
            helm_installation
            exit 0

        elif [[ ${flag} =~ ^-t$ ]]; then
            TERMINAL_CONFIG=true
        
        else
            echo_yellow "Invalid argument"
            print_help
            exit 1
        fi
    done

    # check configure_terminal after the loop to set FORCE
    # even if the script is called with -f after -t
    if [[ ${TERMINAL_CONFIG} == true ]]; then
        curl_installation
        install_fonts
        configure_terminal
        configure_tilix
	exit 0
    fi

}


main "$@"
