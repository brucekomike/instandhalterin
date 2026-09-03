#!/bin/bash

export remote_host=$1
shift
echo ssh $remote_host -t "$@"
ssh $remote_host -t "$@"
