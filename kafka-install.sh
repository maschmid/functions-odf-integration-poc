#!/usr/bin/env bash

subscribe_amq_streams() {
  # TODO: workaround for https://issues.redhat.com/browse/ENTMQST-3047
  startingCSV=$(oc get packagemanifest amq-streams -n openshift-marketplace -o json | jq -r '.status.channels[] | select(.name == "stable") | .currentCSV')
  oc create -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: amq-streams
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: amq-streams
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: $startingCSV
EOF
}

create_kafka() {
  oc create -f - <<EOF
apiVersion: kafka.strimzi.io/v1
kind: Kafka
metadata:
  name: my-cluster
  namespace: kafka
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      auto.create.topics.enable: 'false'
    authorization:
      superUsers:
        - ANONYMOUS
      type: simple
    listeners:
    - name: plain
      port: 9092
      tls: false
      type: internal
    - authentication:
        type: tls
      name: tls
      port: 9093
      tls: true
      type: internal
    - authentication:
        type: scram-sha-512
      name: sasltls
      port: 9094
      tls: true
      type: internal
    - authentication:
        type: scram-sha-512
      name: saslplain
      port: 9095
      tls: false
      type: internal
    - name: tlsnoauth
      port: 9096
      type: internal
      tls: true
  entityOperator:
    topicOperator: {}
    userOperator: {}
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata:
  name: kafka
  namespace: kafka
  labels:
    strimzi.io/cluster: my-cluster
spec:
  replicas: 3
  roles:
    - controller
    - broker
  storage:
    type: jbod
    volumes:
    - id: 0
      type: persistent-claim
      size: 100Gi
      deleteClaim: false
  resources:
    requests:
      memory: 2Gi
      cpu: "300m"
    limits:
      memory: 4Gi
      cpu: "4"
EOF

  oc wait --for=condition=Ready kafka.kafka.strimzi.io my-cluster -n kafka --timeout=6m
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

oc new-project kafka
subscribe_amq_streams
wait_for_csv openshift-operators amq-streams
create_kafka

