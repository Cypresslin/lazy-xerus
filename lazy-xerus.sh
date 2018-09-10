#!/bin/bash
#
# Laziness is humanity  _(:3 」∠)_
#
# Modify the files in lists/ as you wish, then run ./lazy-xerus.sh
# And let this script do the configuration / installation for you on your fresh
# installed Ubuntu, no matter you're running Unity or Gnome!
#
# Kudos to Nicolas Bernaerts for the gnomeshell-extension-manage script
# Author: P.-H Lin
# Source: https://github.com/Cypresslin/lazy-xerus
# License: GPLv3
#

TMPFILE='lazy-xerus.tmp'

# ---- Function to check config files ----
function validator() {
    [ ! -f $1 ] && echo "$1 does not exist, skipping it" && return 1
    lines=`wc -l $1 | awk '{print $1}'`
    [ $lines -le 1 ] && echo "$1 does not valid, skipping it" && return 2
    return 0
}

# ---- Function for reading the list files ----
function reader() {
    local lines
    data=""
    validator $1
    [ $? -ne 0 ] && return
    mapfile -t data < $1
    # The first line is a comment, get rid of it
    unset data[0]
    data=("${data[@]}")
}

# ---- Function to initialize all the variables ----
function init() {
    local dir="lists"

    # Check if it's a second run
    if [ -f $TMPFILE ]; then
        reader "$dir/inst-input-method.txt"
        # Only need one line result here, so use an array
        INPUT_METHOD=("${data[@]}")
        return
    fi

    # === Package to install ===
    reader "$dir/inst-utilities.txt"
    UTILITIES="${data[@]}"

    reader "$dir/inst-input-method.txt"
    INPUT_METHOD="${data[@]}"

    reader "$dir/inst-multimedia.txt"
    MULTIMEDIA="${data[@]}"

    PKG_INST="$UTILITIES $INPUT_METHOD $MULTIMEDIA"

    # === Third party software to be installed ===
    reader "$dir/inst-thirdparty.txt"
    THIRD_PARTIES=("${data[@]}")

    # === Package to be removed ===
    reader "$dir/rm-general.txt"
    RM_GENERAL="${data[@]}"

    reader "$dir/rm-unity.txt"
    RM_UNITY="${data[@]}"

    reader "$dir/rm-gnome.txt"
    RM_GNOME="${data[@]}"

    # Ask user to remove basero if the optical drive does not exist
    if [ ! -b /dev/sr0 ]; then
        yn="Y"
        dpkg -s brasero &> /dev/null
        if [ $? -eq 0 ]; then
            echo "Optical drive /dev/sr0 not detected"
            read -p "Do you want to remove brasero, the CD/DVD burning tool? (Y/n): " yn
            [ "$yn" != "n" ] && RM_GENERAL="$RM_GENERAL brasero-common"
        fi
    fi

    # Ask user to remove the default ibus IME if other IME selected
    validator "$dir/inst-input-method.txt"
    if [ $? -eq 0 ]; then
        echo "$INPUT_METHOD" | grep ibus &> /dev/null
        if [ $? -ne 0 ]; then
            yn="Y"
            echo "ibus was not detected in inst-input-method.txt"
            echo "Do you want to remove ibus, the default input method?"
            read -p "WARNING - remove ibus might get ubuntu-desktop removed (N/y): " yn
            [ "$yn" == "y" ] && RM_GENERAL="$RM_GENERAL ibus ibus-gtk ibus-gtk3"
        fi
    fi

    PKG_RM="$RM_GENERAL"

    # === Program to be pinned/unpinned from the launcher ===
    reader "$dir/launcher-pin.txt"
    SHORTCUTS="${data[@]}"

    reader "$dir/launcher-unpin.txt"
    UNPIN="${data[@]}"

    # === Gnome Extensions to install for Gnome Ubuntu ===
    reader "$dir/gnome-extension.txt"
    EXTENSION="${data[@]}"

    # === vim configs, just put filename here ===
    VIMCONFIGS="$dir/config-vim.txt"

    # === GIT configs ===
    validator "$dir/config-git.txt"
    if [ $? -eq 0 ]; then
        # Checking git tool
        command -v git &> /dev/null
        if [ $? -ne 0 ]; then
            echo "$PKG_INST" | grep -w git &> /dev/null
            if [ $? -ne 0 ]; then
                echo "Error: package 'git' was neither installed nor on the installation list"
                echo "       But config-git.txt present, please correct this issue."
                exit
            fi
        fi
        echo "GIT config requested, checking your GITNAME, GITMAIL setting..."
        grep "user.name \$GITNAME" "$dir/config-git.txt" &> /dev/null
        [ $? -eq 0 ] && read -p "GITNAME: " GITNAME
        grep "user.email \$GITMAIL" "$dir/config-git.txt" &> /dev/null
        [ $? -eq 0 ] && read -p "GITMAIL: " GITMAIL
    fi
    reader "$dir/config-git.txt"
    GIT_CONFIGS=("${data[@]}")

    # === Terminal configs ===
    reader "$dir/config-terminal.txt"
    TERMINAL_CONFIGS=("${data[@]}")

    # === Desktop configs ===
    reader "$dir/config-desktop.txt"
    DESKTOP_CONFIGS=("${data[@]}")
}

# ---- Environment check ----
function env_check() {
    if [ $UID -eq 0 ]; then
        echo "Don't run this script as root"
        exit 1
    fi

    if [ "$DESKTOP_SESSION" == "gnome" ]; then
        PKG_RM="$PKG_RM $RM_GNOME"
    else  # including 17.10, in which DESKTOP_SESSION=ubuntu but gnome-shell also exist
        PKG_RM="$PKG_RM $RM_UNITY"
    fi
    # check network connection here
    nc -z 8.8.8.8 53 &>/dev/null
    [ $? -ne 0 ] && echo "No network connection!" && exit 1
}

# ---- Remove unwanted packages ----
function pkgs_rm() {
    # Iterate through these packages to make sure it's installed
    local newlist=''
    for item in ${PKG_RM[@]}
    do
        dpkg -s $item &> /dev/null
        [ $? -eq 0 ] && newlist="$newlist $item"
    done
    PKG_RM="$newlist"
    sudo apt remove --purge -y -q $PKG_RM
    sudo apt-get autoremove --purge -y -q
}

# ---- Install desired packages ----
function pkgs_inst() {
    sudo apt update -qq
    sudo apt install -y -q $PKG_INST

    # Install third-party tools here
    count=0
    while [ "x${THIRD_PARTIES[count]}" != "x" ]
    do
        app=`echo ${THIRD_PARTIES[count]} | awk {'print $1'}`
        link=`echo ${THIRD_PARTIES[count]} | awk {'print $2'}`
        echo "Trying to install $app with dpkg"
        command -v $app &> /dev/null
        if [ $? -ne 0 ]; then
            wget --show-progress -q $link -O /tmp/$app.deb
            if [ $? -eq 0 ]; then
                sudo dpkg -i /tmp/$app.deb
            fi
        fi
        count=$(( $count + 1 ))
    done

    # Fix all the dependency issues here
    sudo apt-get -f install -y

    # == install the gnome extesion
    if [ "$DESKTOP_SESSION" == "gnome" ]; then
        wget -O /tmp/gnome-ext-installer.sh https://raw.githubusercontent.com/NicolasBernaerts/ubuntu-scripts/master/ubuntugnome/gnomeshell-extension-manage
        if [ $? -eq 0 ]; then
            for item in ${EXTENSION[@]}
            do
                # Parse the ID here
                id=`echo $item | awk -F"/" '{print $5}'`
                bash /tmp/gnome-ext-installer.sh --install --extension-id $id
            done
            echo "Restarting your gnome-shell"
            gnome-shell --replace &
        fi
    fi

    # Install drivers, there might be different versions for nvidia so choose the latest one
    drivers="`ubuntu-drivers list | grep -v nvidia` `ubuntu-drivers list | grep nvidia | sort | tail -n1`"
    sudo apt-get install -y -q $drivers

    # Dist-upgrade
    sudo apt-get dist-upgrade -y -q
}


# ---- Change launcher favorites ----
# Must be placed after pkgs_inst function
function change_shortcuts() {
    local list=''
    local newlist=''
    local item=''
    local skip=''
    local target=''
    local newapp=''

    command -v gnome-shell &> /dev/null
    if [ $? -eq 0 ]; then  # Not checking DESKTOP_SESSION for 17.10
        local list=`gsettings get org.gnome.shell favorite-apps | sed 's/[][]//g'`
    else
        local list=`gsettings get com.canonical.Unity.Launcher favorites | sed 's/[][]//g'`
    fi

    # Remove UNPIN items
    newlist=""
    for item in ${list[@]}
    do
        skip=false
        for target in ${UNPIN[@]}
        do
            echo "$item" | grep "$target" &> /dev/null
            if [ $? -eq 0 ]; then
                echo "Unpin $target"
                skip=true
                break
            fi
        done
        if [ $skip == false ]; then
            newlist="$newlist $item"
        fi
    done
    # Remove the trailing comma
    list=`echo "$newlist" | sed 's/,$//'`

    newapp=""
    for item in ${SHORTCUTS[@]}
    do
        # Check target existence first
        if [ -f /usr/share/applications/$item.desktop ]; then
            newapp="'$item.desktop',$newapp"
        else
            echo "$item not found in /usr/share/applications"
        fi
    done
    # Remove the trailing comma
    newapp=`echo "$newapp" | sed 's/,$//'`
    newlist="[$list, $newapp]"

    command -v gnome-shell &> /dev/null
    if [ $? -eq 0 ]; then  # Not checking DESKTOP_SESSION for 17.10
        gsettings set org.gnome.shell favorite-apps "$newlist"
    else
        gsettings set com.canonical.Unity.Launcher favorites "$newlist"
    fi
}

# ---- Config the system ----
function configuration() {
    # Change terminal color theme
    local profile=''
    local fullpath=''
    local count=''
    profile=`gsettings get org.gnome.Terminal.ProfilesList list | awk -F"'" '{print$2}'`
    fullpath="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$profile/"
    count=0
    while [ "x${TERMINAL_CONFIGS[count]}" != "x" ]
    do
        gsettings set $fullpath ${TERMINAL_CONFIGS[count]}
        count=$(( $count + 1 ))
    done

    # Disable locale forwarding
    sudo sed -i 's/^    SendEnv LANG LC_\*/#   SendEnv LANG LC_\*/' /etc/ssh/ssh_config

    # Setting for vim
    [ -f $VIMCONFIGS ] && cat $VIMCONFIGS > $HOME/.vimrc

    # Setting for git
    count=0
    command -v git &> /dev/null
    if [ $? -eq 0 ]; then
        while [ "x${GIT_CONFIGS[count]}" != "x" ]
        do
            prop=`echo ${GIT_CONFIGS[count]} | awk {'print $1'}`
            value=`echo ${GIT_CONFIGS[count]} | awk {'print $2'}`
            # Stupid way to use the user-defined variable
            [ "$value" == "\$GITNAME" ] && value="$GITNAME"
            [ "$value" == "\$GITMAIL" ] && value="$GITMAIL"
            git config --global "$prop" "$value"
            count=$(( $count + 1 ))
        done
    else
        echo "Package 'git' was not installed."
    fi

    # Setting for desktop
    count=0
    while [ "x${DESKTOP_CONFIGS[count]}" != "x" ]
    do
       key=`echo ${DESKTOP_CONFIGS[count]} | awk {'print $1'}`
       property=`echo ${DESKTOP_CONFIGS[count]} | awk {'print $2'}`
       value=`echo ${DESKTOP_CONFIGS[count]} | awk {'print $3'}`
       gsettings get "$key" "$property" &> /dev/null
       [ $? -eq 0 ] && gsettings set "$key" "$property" "$value"
       count=$(( $count + 1 ))
    done
}


# ---- Configure IME ----
function config_ime() {
    # Checking if the current IME is the desired one
    # im-config -m output format:
    # 1. active configuration (system)
    # 2. active configuration (user)
    # 3. automatic configuration for the current locale
    # 4. override configuration for the current locale
    # 5. automatic configuration for most locales
    # the second is the one we want
    local target=''
    target=`echo ${INPUT_METHOD[0]} | awk {'print $1'}`
    im-config -m | sed -n '2p' | grep $target &> /dev/null
    if [ $? -ne 0 ]; then
        # Switch input method to the selected one
        im-config -n $target
        echo "You will have to logout for the input method, run this script again later."
        echo "Script terminates now"
        touch $TMPFILE
        gnome-session-quit
        exit
    fi

    # Enable fcitx wrappers if selected
    if [ -f $TMPFILE ]; then
        echo ${INPUT_METHOD[@]} | grep 'fcitx' &> /dev/null
        if [ $? -eq 0 ]; then
            if [ -f $HOME/.config/fcitx/profile ]; then
                for item in ${INPUT_METHOD[@]}
                do
                    target=`echo $item | sed 's/fcitx-//'`
                    sed -i "s/$target:False/$target:True/" $HOME/.config/fcitx/profile
                done
                fcitx-remote -r
            else
                echo "fcitx config file not found, maybe it's not enabled properly?"
            fi
        fi
    fi
}

function help_msg {
    echo "Usage: $0 [-s]"
    echo -e "\t-h : Print this help message and exit."
    echo -e "\t-s : Run this script step by step."
}


step=false
while getopts :sh opt; do
  case $opt in
    s)
      echo "Run this script step by step."
      step=true
      ;;
    h)
      help_msg
      exit
      ;;
    \?)
      echo "Invalid option: -$OPTARG"
      help_msg
      exit
      ;;
  esac
done

if [ ! -f $TMPFILE ]; then
    # first run
    init
    env_check
    echo "Removing unwanted packages"
    [ $step == 'true' ] && read -p "Hit enter to continue"
    pkgs_rm
    echo "Installing assigned packages"
    [ $step == 'true' ] && read -p "Hit enter to continue"
    pkgs_inst
    echo "Changing launcher items"
    [ $step == 'true' ] && read -p "Hit enter to continue"
    change_shortcuts
    echo "Configuring your system"
    [ $step == 'true' ] && read -p "Hit enter to continue"
    configuration
    echo "Configuring your IME"
    [ $step == 'true' ] && read -p "Hit enter to continue"
    config_ime
else
    # second run
    init
    echo "Configuring your IME"
    config_ime
    rm $TMPFILE
    echo "All DONE, enjoy!"
fi
