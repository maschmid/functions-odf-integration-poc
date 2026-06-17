#!/usr/bin/env bash
#
# Copies the worker machineset, creates a specific machineset for ODF

set -Eeuxo pipefail

# Loops until duration (car) is exceeded or command (cdr) returns non-zero
function wait_while {
  local seconds timeout interval
  interval=2
  seconds=0
  timeout=$1
  shift
  while eval "$*"; do
    seconds=$(( seconds + interval ))
    sleep $interval
    echo -n '.'
    [[ $seconds -gt $timeout ]] && echo "Time out of ${timeout} exceeded" && return 1
  done
  if [[ "$seconds" != '0' ]]; then
    echo ''
  fi
  return 0
} 

# get the first worker machineset name
orig=$(oc get machineset -n openshift-machine-api -o name | grep 'worker-' | head -n1 | sed 's|machineset.machine.openshift.io/||')
kind=$(oc get machineset -n openshift-machine-api "$orig" -o json | jq -r .spec.template.spec.providerSpec.value.kind)

# Default OpenStack flavor on PSI
if [ "$kind" = "OpenstackProviderSpec" ]; then
  flavor=ci.standard.xxxl
elif [ "$kind" = "AWSMachineProviderConfig" ]; then
  # m5.xlarge -> m5.2xlarge
  flavor=$(oc get machineset -n openshift-machine-api "$orig" -o json | jq -r .spec.template.spec.providerSpec.value.instanceType | sed -E 's/([^\.]+)\.xlarge/\1.2xlarge/')
else
  flavor=""
fi

vars=$(getopt -o f: --long flavor: -- "$@")
eval set -- "$vars"

for opt; do
  case "$opt" in
    -f|--flavor)
      flavor=$2
      shift 2
      ;;
  esac
done

if [ -z "${flavor}" ]
then
  echo "flavor not defined nor cannot determine a proper default value"
  exit 1
fi

new=${orig}-odf

oc get machineset -n openshift-machine-api "${orig}" -o json | \
  jq ".metadata.name = \"$new\"" | \
  jq ".spec.selector.matchLabels[\"machine.openshift.io/cluster-api-machineset\"] = \"$new\"" | \
  jq ".spec.template.metadata.labels[\"machine.openshift.io/cluster-api-machineset\"] = \"$new\"" | \
  jq ".spec.template.spec.providerSpec.value.flavor = \"$flavor\"" | \
  jq ".spec.template.spec.providerSpec.value.instanceType = \"$flavor\"" | \
  jq '.spec.template.spec.taints = [{"effect":"NoSchedule","key":"node.ocs.openshift.io/storage","value":"true"}]' | \
  jq ".spec.replicas = 3" | \
  jq ".spec.template.spec.metadata.labels[\"cluster.ocs.openshift.io/openshift-storage\"] = \"\"" | \
  jq "del(.status)" | \
  oc create -f -

function machinesetready {
  [ true = "$(oc get machineset -n openshift-machine-api "${new}" -o json | jq -r '.status.replicas == .status.readyReplicas')" ]
}

wait_while 1800 ! machinesetready

