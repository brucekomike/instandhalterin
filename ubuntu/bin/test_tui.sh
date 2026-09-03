#!/bin/bash

export remote_host=$1
shift
echo $@
ssh $remote_host -t 'dialog --title "Connection Test" --msgbox "CLI Dialog is working properly!" 8 45'
