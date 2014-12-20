#!/bin/bash

##### Version 0.1 #####

userdb="/etc/dovecot/users"
mailboxmap="/etc/postfix/virtual/virtual-mailbox-maps.cf"
authsock="/var/spool/postfix/private/auth"
vhome_prefix="/var/mail/vhome"
mail_user="vmail"

add_user () {

    username=$(echo "$adduser" | cut -f1 -d "@")
    domain=$(echo "$adduser" | cut -f2 -d "@")

    if [[ -n "$username" && -n "$domain" ]]; then
        echo -n "Please enter password: "
        read -s password1
        echo
        echo -n "Please enter password again: "
        read -s password2
            if [[ "$password1" = "$password2" ]]; then
                userpass="$(doveadm pw -p "$password1" -s SHA512-CRYPT)"
	    else
                echo -n "Password mismatch, please try again"
                exit 1
            fi
    else
         echo "Nothing to do, abort!"
	 exit 1
    fi
   
    #  Add given name@domain to Dovecot user DB

    if [[ -f "$userdb" ]]; then
        echo "Adding $username@$domain to Dovecot user database!"
        echo "$username@$domain:$userpass:::" >> "$userdb"
    else
        echo -e "\nDovecot user database not found!"
        exit 1
    fi

    # Update Postfix virtual mailbox map

    if [[ -f "$mailboxmap" ]]; then
        echo "Updating Postfix maps!"
        echo "$username@$domain $domain/$username" >> "$mailboxmap"
        postmap hash:/"$mailboxmap"
        echo "Hashing map is done!"
        postfix reload > /dev/null 2>&1
    else
        echo "Postfix map not exist or have been moved to another directory!"
        exit 1
    fi

    # Create Dovecot home directory if non exist
    
    if [[ -d $vhome_prefix ]] || mkdir $vhome_prefix; 
       then
       user_vhome="$vhome_prefix/$domain/$username"
       mkdir -p "$user_vhome"
       chown -R "$mail_user:$mail_user" "$vhome_prefix/$domain"
       chmod -R 770 "$vhome_prefix/$domain"
       echo "Successfully created $username@$domain vhome directory!"
    else
       echo "$username@$domain Dovecot home directory not created"
    fi
    
    exit 0
}

delete_user () {
    if [[ "$(grep ^$deluser.*:::$ $userdb)" ]]; then

        username=$(echo "$deluser" | cut -f1 -d "@")
        domain=$(echo "$deluser" | cut -f2 -d "@")

        # Delete given name@domain from Dovecot user DB and Postfix mailbox map

        echo "Do you really want to delete $deluser? [Y/N]"
        read -s -n 1 delete
        case $delete in
            y|Y)
                sed -i "/^$deluser.*:::$/d" $userdb
                sed -i "/^$deluser/d" $mailboxmap
                postmap $mailboxmap
                postfix reload > /dev/null 2>&1
                echo "User account have been successfully deleted!"
            
                # Delete users mail directory 

                echo "Do you really want to delete $deluser mail directory? [Y/N]"
                read -s -n 1 delete2
                case $delete2 in
                    y|Y)
                        if [[ -d "/var/mail/vhosts/$domain/$username" ]]; then
                            rm -rf "/var/mail/vhosts/$domain/$username"
                            echo "$deluser mail directory succesfully deleted!"                               
                        else
                            echo "Directory not found!"
                        fi
                        ;;
                    n|N)
                        echo "Aborting..."
                esac
               
                # Delete users Dovecot home directory

                echo "Do you really want to delete $deluser home directory? [Y/N]"
                read -s -n 1 delete3
                case $delete3 in
                    y|Y)
                        if [[ -d "/var/mail/vhome/$domain/$username" ]]; then
                            rm -rf "/var/mail/vhome/$domain/$username"
                            echo "$deluser vhome directory succesfully deleted!"
                        else
                            echo "Directory not found!"
                        fi
                        ;;
                    n|N)
                        echo "Aborting..."
                esac
                ;;
            n|N)
                echo "Aborting..."
                exit 0
                ;;
        esac        

    else
        echo "Error! User not found..."
        exit 1
    fi
}

list_users () {

    if [[ -f "$userdb" ]]; then
        awk -F: '/./ {print $1}' "$userdb"
    else
        echo "User database not exist or have been moved to another directory!"
        exit 1
    fi
}

test_auth () {

    if [[ "$(grep ^$testuser: $userdb)" ]]; then    
        doveadm auth test -a $authsock $testuser
    else
        echo "User not found!"
        exit 1
    fi
}

change_pass () {

    if [[ "$(grep ^$chguser: $userdb)" ]]; then
        echo "Please enter new password: "
        read -s new_password1
        echo
        echo "Please enter new password again: "
        read -s new_password2

        if [[ "$new_password1" = "$new_password2" ]]; then
            new_userpass="$(doveadm pw -p $new_password1 -s SHA512-CRYPT)"
        else
            echo "Password mismatch, please try again"
            exit 1
        fi

        sed -i "s#^\($chguser:\){SHA512-CRYPT}[^:]*#\1$new_userpass#" "$userdb"

        if [ $? -eq 0 ]; then
            echo "Password successfully changed"
            exit 0
        else
            echo "Password not changed, abort"
            exit 1
        fi
    else
        echo "User not found! Aborting..."
        exit 1
    fi
}

help_usage () {

 echo "USAGE:
 $(basename $0) [options] [arg]

 Options:

 -a, --add 		Add user to Dovecot user database
 -l, --list 		List all users
 -p, --pass 		Change password for given user account
 -t, --test 		Test user auth credentials
 -d, --delete 		Delete user from Dovecot user database
 -h, --help 		Show this usage instruction
"
}

case "$1" in
     --add|-a)
        shift
        adduser="$1"
        add_user
        ;;
     --list|-l)
        list_users
        ;;
     --test|-t)
         shift
         testuser="$1"
         test_auth
         ;;
     --pass|-p)
        shift
        chguser="$1"
        change_pass
        ;;
     --delete|-d)
        shift
        deluser="$1"
        delete_user
        ;;
      --help|-h)
        help_usage
        ;;
     *)
        echo "Unknown command"
        ;;
esac
