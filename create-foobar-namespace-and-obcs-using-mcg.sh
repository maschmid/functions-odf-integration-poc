#!/usr/bin/env bash

namespace=foobar

function create_namespace() {
  oc new-project "${namespace}"
}

function create_obc() {
  oc create -f - <<EOF
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: $1
  namespace: $namespace
spec:
  additionalConfig:
    bucketclass: noobaa-default-bucket-class
  bucketName: $1
  storageClassName: openshift-storage.noobaa.io
EOF
}

create_namespace
create_obc "foo-bucket"
create_obc "foo-bucket-resized"

