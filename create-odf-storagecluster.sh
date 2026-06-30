#!/usr/bin/env bash

set -Eeuxo pipefail

orig=$(oc get machineset -n openshift-machine-api -o name | grep 'worker-' | head -n1 | sed 's|machineset.machine.openshift.io/||')
kind=$(oc get machineset -n openshift-machine-api "$orig" -o json | jq -r .spec.template.spec.providerSpec.value.kind)

if [ "$kind" = "OpenstackProviderSpec" ]; then
  storage_class=standard-csi
  storage_size=128Gi
  deviceset_name=ocs-deviceset-standard-csi
elif [ "$kind" = "AWSMachineProviderConfig" ]; then
  storage_class=gp3-csi
  storage_size=128Gi
  deviceset_name=ocs-deviceset-gp3-csi
else
  echo "Unknown provider kind: $kind"
  exit 1
fi

function create_odf_storagecluster() {
  oc create -f - <<EOF
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  annotations:
    uninstall.ocs.openshift.io/cleanup-policy: delete
    uninstall.ocs.openshift.io/mode: graceful
  name: ocs-storagecluster
  namespace: openshift-storage
spec:
  arbiter: {}
  encryption:
    keyRotation:
      schedule: '@weekly'
    kms: {}
  externalStorage: {}
  managedResources:
    cephBlockPools: {}
    cephCluster: {}
    cephDashboard: {}
    cephFilesystems: {}
    cephNonResilientPools: {}
    cephObjectStoreUsers: {}
    cephObjectStores: {}
    cephRBDMirror: {}
    cephToolbox: {}
  network:
    connections:
      encryption: {}
    multiClusterService: {}
  nodeTopologies: {}
  resourceProfile: lean
  storageDeviceSets:
  - config: {}
    count: 1
    dataPVCTemplate:
      metadata: {}
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: ${storage_size}
        storageClassName: ${storage_class}
        volumeMode: Block
      status: {}
    deviceClass: ssd
    name: ${deviceset_name}
    placement: {}
    portable: true
    preparePlacement: {}
    replica: 3
    resources: {}
EOF
}

create_odf_storagecluster
oc wait --for=jsonpath='{.status.phase}'=Ready storagecluster ocs-storagecluster -n openshift-storage --timeout=30m

