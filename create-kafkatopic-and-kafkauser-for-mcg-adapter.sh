#!/usr/bin/env bash

mcg_adapter_topic="mcg-adapter-notifications"

function create_mcg_adapter_topic() {
  cat <<-EOF | oc apply -f -
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: ${mcg_adapter_topic}
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
}

# Account for noobaa to publish to the mcg-adapter-notifications topic
function create_noobaa_notifications_kafka_user() {
  cat <<-EOF | oc apply -f -
apiVersion: kafka.strimzi.io/v1
kind: KafkaUser
metadata:
  name: noobaa-notifications-user
  namespace: kafka
  labels:
    strimzi.io/cluster: my-cluster
spec:
  authentication:
    type: scram-sha-512
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: "${mcg_adapter_topic}"
          patternType: literal
        operations:
          - Read
          - Describe
          - Write
          - Create
          - Delete
        host: "*"
      - resource:
          type: group
          name: "${mcg_adapter_topic}"
          patternType: literal
        operations:
          - Describe
        host: "*"
EOF
}

# TODO: for now just grant all ops to all topics on the cluster
function create_mcg_adapter_kafka_user() {
  cat <<-EOF | oc apply -f -
apiVersion: kafka.strimzi.io/v1
kind: KafkaUser
metadata:
  name: mcg-adapter-user
  namespace: kafka
  labels:
    strimzi.io/cluster: my-cluster
spec:
  authentication:
    type: scram-sha-512
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: "*"
        operations:
          - Read
          - Describe
          - Write
          - Create
          - Delete
        host: "*"
      - resource:
          type: group
          name: "*"
        operations:
          - Read
        host: "*"
EOF
}

create_mcg_adapter_topic
create_noobaa_notifications_kafka_user
create_mcg_adapter_kafka_user

