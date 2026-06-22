#!/usr/bin/env bash

set -Eeuxo pipefail

subscribe_odf() {
  oc create -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-storage
  labels:
    openshift.io/cluster-monitoring: "true"
EOF

  oc create -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  generateName: openshift-storage-
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
  upgradeStrategy: Default
EOF

  oc create -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: odf-operator
  namespace: openshift-storage
spec:
  channel: stable-4.21
  installPlanApproval: Automatic
  name: odf-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
}

wait_for_csv() {
  local ns=$1
  local subscription=$2

  while true
  do
    csv=$(oc get subscriptions.operators.coreos.com ${subscription} -n ${ns} -o=custom-columns=INSTALLED_CSV:.status.installedCSV --no-headers=true)
    echo "csv: $csv"
    if [ x$csv != "x" -a x$csv != x"<none>" ]
    then
      break
    fi
    sleep 1
  done

  while true
  do
    phase=$(oc get clusterserviceversions.operators.coreos.com -n $ns $csv -o=custom-columns=PHASE:.status.phase --no-headers=true)
    echo "phase: $phase"
    if [ x$phase = x"Succeeded" ]
    then
      break
    fi
    sleep 1
  done
}

function enable_odf_console_plugin() {
  oc wait --for=create consoleplugin odf-console --timeout=20m
  oc patch console.operator.openshift.io cluster --type json -p='[{"op":"add","path":"/spec/plugins/-","value":"odf-console"}]'
}

subscribe_odf
wait_for_csv openshift-storage odf-operator
enable_odf_console_plugin


