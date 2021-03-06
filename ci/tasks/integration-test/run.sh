#!/bin/bash

set -eu

fail () { echo "FAILURE: $1" >&2 ; exit 1 ; }

wget -qO /tmp/release.tgz https://s3.amazonaws.com/bosh-compiled-release-tarballs/bosh-260.5-ubuntu-trusty-3312.15-20170124-025145-688314225-20170124025151.tgz?versionId=XdnsJBm4uh.wTJ1aKy5BZ.B.NtBOZFTD

cd repo

start-bosh \
    -o /usr/local/bosh-deployment/local-bosh-release.yml \
    -o $PWD/ci/tasks/integration-test/bosh-ops.yml \
    -v local_bosh_release=/tmp/release.tgz

source /tmp/local-bosh/director/env

bosh upload-stemcell \
  --sha1=4cf583da9e2388480e93f348b52c60374b9a097e \
  https://s3.amazonaws.com/bosh-core-stemcells/warden/bosh-stemcell-3363.15-warden-boshlite-ubuntu-trusty-go_agent.tgz

export BOSH_DEPLOYMENT=integration-test

bosh -n deploy \
  --vars-store=/tmp/deployment-vars.yml \
  -v repo_dir="$PWD" \
  ci/tasks/integration-test/deployment.yml

bosh ssh role1/0 '
  set -e
  sudo ping -c 5 192.168.206.1 | sudo tee -a /var/vcap/sys/log/openvpn/client1-stdout.log
  sleep 5
  sudo /var/vcap/bosh/bin/monit stop openvpn-client1
'

mkdir -p role1-logs

bosh scp role1/0:/var/vcap/sys/log/openvpn/client1-stdout.log role1-logs
bosh scp role1/0:/var/vcap/sys/log/openvpn/stdout.log role1-logs

if ! grep -q "TCP connection established with" role1-logs/client1-stdout.log* ; then
  fail "Client failed to connect to server"
elif ! grep -q "/sbin/ifconfig tun1 192.168.206.2 netmask 255.255.255.0" role1-logs/client1-stdout.log* ; then
  fail "Client failed to establish tunnel correctly"
elif ! grep -q "Initialization Sequence Completed" role1-logs/client1-stdout.log* ; then
  fail "Client did not complete initialization sequence"
elif ! grep -q "64 bytes from 192.168.206.1" role1-logs/client1-stdout.log* ; then
  fail "Client was unable to ping the remote gateway"
elif ! grep -q "process exiting" role1-logs/client1-stdout.log* ; then
  fail "Client did not exit cleanly"
fi

bosh ssh role2/0 '
  set -e
  sudo ping -c 5 192.168.202.1 | sudo tee -a /var/vcap/sys/log/openvpn/client1-stdout.log
  sleep 5
  sudo /var/vcap/bosh/bin/monit stop openvpn-client1
'

mkdir -p role2-logs

bosh scp role2/0:/var/vcap/sys/log/openvpn/client1-stdout.log role2-logs
bosh scp role2/0:/var/vcap/sys/log/openvpn/stdout.log role2-logs

if ! grep -q "TCP connection established with" role2-logs/client1-stdout.log* ; then
  fail "Client failed to connect to server"
elif ! grep -q "/sbin/ifconfig tun1 192.168.202.2 netmask 255.255.255.0" role2-logs/client1-stdout.log* ; then
  fail "Client failed to establish tunnel correctly"
elif ! grep -q "Initialization Sequence Completed" role2-logs/client1-stdout.log* ; then
  fail "Client did not complete initialization sequence"
elif ! grep -q "64 bytes from 192.168.202.1" role2-logs/client1-stdout.log* ; then
  fail "Client was unable to ping the remote gateway"
elif ! grep -q "process exiting" role2-logs/client1-stdout.log* ; then
  fail "Client did not exit cleanly"
fi

bosh -n delete-deployment

#
# stop-bosh
#

bosh -n clean-up --all

set +u

source /etc/profile.d/chruby.sh

chruby 2.3.1

bosh delete-env "/tmp/local-bosh/director/bosh-director.yml" \
  --vars-store="/tmp/local-bosh/director/creds.yml" \
  --state="/tmp/local-bosh/director/state.json"
