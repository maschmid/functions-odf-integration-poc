#!/usr/bin/env bash

set -Eeuxo pipefail

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
            storage: 128Gi
        storageClassName: gp3-csi
        volumeMode: Block
      status: {}
    deviceClass: ssd
    name: ocs-deviceset-gp3-csi
    placement: {}
    portable: true
    preparePlacement: {}
    replica: 3
    resources: {}
EOF
}

create_odf_storagecluster
oc wait --for=jsonpath='{.status.phase}'=Ready storagecluster ocs-storagecluster -n openshift-storage --timeout=30m

