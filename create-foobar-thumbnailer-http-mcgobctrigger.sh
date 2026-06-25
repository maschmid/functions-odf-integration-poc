#!/usr/bin/env bash

oc create -f - <<EOF
apiVersion: internal.functions.dev/v1alpha1
kind: MCGOBCTrigger
metadata:
  namespace: foobar
  name: foo-bucket-thumbnailer-trigger
spec:
  obc:
    name: foo-bucket
  events:
  - "s3:ObjectCreated:*"
  triggers:
  - uri: http://thumbnailer.foobar.svc.cluster.local
EOF


