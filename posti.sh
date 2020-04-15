#!/usr/bin/env bash

main() {
    check_root_and_exit
    set_variables
    set_package_manager
    handle_flags "$@"
    update_and_upgrade
    curl_installation
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
        echo "This script must be executed with root privilages"
        exit 1
    fi
}

set_variables() {
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    yellow=$(tput setaf 3)
    reset=$(tput sgr0)
    log="/tmp/posti.log"
    SUDO_USER=${SUDO_USER:='root'}
    home_dir_path=$(grep ${SUDO_USER} /etc/passwd |awk -F ':' '{print $6}')
}

echo_white() {
    echo "$*" |tee -a ${log}
}

echo_red() {
    echo "${red}$*${reset}" |tee -a ${log}
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
		## Print text with a spinner
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

	## Print a new line outside the loop so it will not interrupt with the it
	## and will not interrupt with the upcoming text of the script
	printf "\n\n"
}

set_package_manager() {
    if command -v apt-get &> /dev/null; then
        pkg_manager="apt"
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

    if [[ ${pkg_manager} == "apt" ]]; then
        send_to_spinner "apt-get update" "System update"
        send_to_spinner "apt-get upgrade -y" "System upgrade"

    elif [[ ${pkg_manager} == "dnf" ]]; then
        send_to_spinner dnf update -y
    fi
}

curl_installation() {
    if ! command -v curl; then
        send_to_spinner "${pkg_manager} install -y curl" "curl installation"
    fi
}

packages_installation() {
    echo_white "Installing packages"
    pkg_array=(git zsh plank ssh code tilix screenfetch virtualbox virtualbox-ext-pack)
    if [[ ${pkg_manager} == "apt" ]]; then
        export DEBIAN_FRONTEND=noninteractive
    fi

    send_to_spinner "add-apt-repository multiverse" "Adding multiverse repo"
    send_to_spinner "apt-get update" "System update"
    for pkg in "${pkg_array[@]}"; do
        send_to_spinner "${pkg_manager} install -y ${pkg}" "${pkg} installation"
    done

    echo_green "Packages installtion finished successfully"

    docker_installation
}

docker_installation() {
    echo_white "Installing docker"
    curl --silent -L -o docker_installation.sh https://get.docker.com
    send_to_spinner "sh docker_installation.sh" "Docker installation"
    # send_to_spinner "$(curl -L https://get.docker.com | sh)" "Docker installation"
    usermod -aG ${SUDO_USER} docker
    
    echo_green "Docker installation finished successfully"
}

configure_terminal() {
        
    usermod -s /usr/bin/zsh $SUDO_USER
    curl --silent -L -o ohmyzsh.sh https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
    send_to_spinner "sh ohmyzsh.sh" "Oh My Zsh installation"
    send_to_spinner "git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-completions" "zsh-completions installation" 
    send_to_spinner "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" "zsh-syntax-highlighting installation"
    send_to_spinner "git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" "zsh-autosuggestions installation"
    if ! [[ -s config/zshrc ]]; then
        echo_red "Failed to find custom zshrc"
        exit 1
    fi

    if [[ -s ${home_dir_path}/.zshrc ]]; then
        mv ${home_dir_path}/.zshrc ${home_dir_path}/.zshrc.bck
    fi

    sed -i "s/%HOME_USER%/${home_dir_path}/" config/zshrc
    cp -f config/zshrc ${home_dir_path}/.zshrc

    echo_green "Terminal configured"

}

configure_tilix() {

    if command -v tilix; then
        gsettings set org.gnome.desktop.default-applications.terminal exec 'tilix'
    fi

    if [[ -s config/tilix.dconf ]]; then
        echo_red "could not detect tilix.dconf, try to clone the repository again"
        exit 1
    fi

    dconf load /com/gexperts/Tilix/ < config/tilix.dconf

    echo_green "Tilix configured"
}

install_fonts() {
    send_to_spinner "curl -L --silent https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf -O ${home_dir_path}/'MesloLGS NF Regular.ttf'" "MesloLGS NF Regular font installation"
    if command -v code &> /dev/null; then
        printf '{\n"terminal.integrated.fontFamily": "MesloLGS NF"\n}\n' >> ${home_dir_path}/.config/Code/User/settings.json
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

    send_to_spinner "curl -L --silent https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash" "Helm 3 installation"
    echo_green "Helm installation finished successfully"
}

print_help() {
    printf "
    Usage: $0 <argumant>

    -d      Install docker
    -h      Print help
    -H      Install helm 3
    -m      Install minikube
    -t      Configure terminal
"
    
}

handle_flags() {

    flags=($@)
    if [[ -z ${flags[@]} ]]; then
        return 0
    fi

    for flag in ${flags[@]}; do 
        if [[ ${flag} =~ ^-h$ ]]; then
            print_help
        
        elif [[ ${flag} =~ ^-d$ ]]; then
            curl_installation
            docker_installation
            
        elif [[ ${flag} =~ ^-m$ ]]; then 
            curl_installation
            minikube_installation
        
        elif [[ ${flag} =~ ^-H$ ]]; then
            curl_installation
            helm_installation
        
        elif [[ ${flag} =~ ^-t$ ]]; then
            curl_installation
            configure_terminal
        
        else
            echo_red "Invalid argument"
            print_help
            exit 1
        fi
    done
        exit 0 
}


main "$@"