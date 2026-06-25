#!/usr/bin/env bash

oc create -f - <<EOF
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: functions-foobar-thumbnailer-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: my-cluster
spec:
  partitions: 8
  replicas: 3
  config:
    retention.ms: 86400000
    cleanup.policy: delete
EOF

oc create -f - <<EOF
apiVersion: internal.functions.dev/v1alpha1
kind: MCGOBCTrigger
metadata:
  namespace: foobar
  name: foo-bucket-thumbnailer-kafka-trigger
spec:
  obc:
    name: foo-bucket
  events:
  - "s3:ObjectCreated:*"
  triggers:
  - kafka:
      topic: functions-foobar-thumbnailer-topic
EOF


