#!/usr/bin/env bash

set -Eeuxo pipefail

function create_noobaa_kafka_sasluser_connection() {
  local name bootstrap topic password_secret_namespace password_secret_name username password
  name=$1
  bootstrap=$2
  topic=$3
  username=$4
  password_secret_namespace=$5
  password_secret_name=$6

  tmp=$(mktemp -d)

  password=$(oc get secret -n "${password_secret_namespace}" "${password_secret_name}" -o jsonpath='{.data.password}' | base64 --decode)

  cat > "$tmp/connect.json" <<EOF
{
  "name": "$name",
  "notification_protocol": "kafka",
  "topic": "$topic",
  "kafka_options_object": {
    "metadata.broker.list": "$bootstrap",
    "security.protocol": "SASL_PLAINTEXT",
    "sasl.mechanism": "SCRAM-SHA-512",
    "sasl.username": "$username",
    "sasl.password": "$password"
  }
}
EOF

  oc delete secret -n openshift-storage "${name}" || true
  oc create secret generic "${name}" --from-file="${tmp}/connect.json" -n openshift-storage

  existing_connections=$(oc get noobaa noobaa -n openshift-storage -o json | jq -c '.spec.bucketNotifications.connections // []')
  updated_connections=$(echo "$existing_connections" | jq -c \
    --arg name "${name}" \
    '[.[] | select(.name != $name)] + [{"name": $name, "namespace": "openshift-storage"}]')

  oc patch noobaa noobaa --type='merge' -n openshift-storage -p '{
  "spec": {
    "bucketNotifications": {
      "connections": '"${updated_connections}"',
      "enabled": true
    }
  }
}'

  # Wait until the change propagates
  echo "Sleeping for 30s to let the noobaa change propagate"
  sleep 30

  rm -rf "${tmp}"
}

connection="mcg-adapter-notifications-connection"
create_noobaa_kafka_sasluser_connection "${connection}" "my-cluster-kafka-bootstrap.kafka.svc:9095" mcg-adapter-notifications noobaa-notifications-user kafka noobaa-notifications-user

NOOBAA_ACCESS_KEY=$(oc extract secret/foo-bucket -n foobar --keys=AWS_ACCESS_KEY_ID --to=- 2>/dev/null); \
NOOBAA_SECRET_KEY=$(oc extract secret/foo-bucket -n foobar --keys=AWS_SECRET_ACCESS_KEY --to=- 2>/dev/null); \
S3_ENDPOINT=https://$(oc get route s3 -n openshift-storage -o json | jq -r ".spec.host")
aws_alias() {
  AWS_ACCESS_KEY_ID=$NOOBAA_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$NOOBAA_SECRET_KEY aws --endpoint "$S3_ENDPOINT" --no-verify-ssl "$@"
}

aws_alias s3api put-bucket-notification --bucket "foo-bucket" --notification-configuration '{
  "TopicConfiguration": {
    "Id": "'$connection'",
    "Events": ["s3:ObjectCreated:*"],
    "Topic": "'${connection}'/connect.json"
  }
}'

