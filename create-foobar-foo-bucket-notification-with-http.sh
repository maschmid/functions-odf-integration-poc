#!/usr/bin/env bash

function create_noobaa_http_connection() {
  local namespace svc port connection
  namespace=$1
  svc=$2
  port=$3

  tmp=$(mktemp -d)

  connection="${namespace}-${svc}-connection"

  cat > "$tmp/connect.json" <<EOF
{
  "name": "$connection",
  "notification_protocol": "http",
  "agent_request_object": {
    "host": "$svc.$namespace.svc.cluster.local",
    "port": $port
   }
}
EOF

  connection="${namespace}-${svc}-connection"

  # Needs to be an admin for these!
  # oc delete secret -n openshift-storage "${connection}" || true # ignore if exists
  oc create secret generic "${connection}" --from-file="${tmp}/connect.json" -n openshift-storage

  existing_connections=$(oc get noobaa noobaa -n openshift-storage -o json | jq -c '.spec.bucketNotifications.connections // []')
  updated_connections=$(echo "$existing_connections" | jq -c \
    --arg name "${connection}" \
    '[.[] | select(.name != $name)] + [{"name": $name, "namespace": "openshift-storage"}]')

  oc patch noobaa noobaa --type='merge' -n openshift-storage -p '{
  "spec": {
    "bucketNotifications": {
      "connections": '"${updated_connections}"',
      "enabled": true
    }
  }
}'

  rm -rf "${tmp}"
}

#create_noobaa_http_connection foobar http-logger 8676
#create_noobaa_http_connection foobar thumbnailer 80

logger_connection="foobar-http-logger-connection"
thumbnailer_connection="foobar-thumbnailer-connection"

NOOBAA_ACCESS_KEY=$(oc extract secret/foo-bucket -n foobar --keys=AWS_ACCESS_KEY_ID --to=- 2>/dev/null); \
NOOBAA_SECRET_KEY=$(oc extract secret/foo-bucket -n foobar --keys=AWS_SECRET_ACCESS_KEY --to=- 2>/dev/null); \
S3_ENDPOINT=https://$(oc get route s3 -n openshift-storage -o json | jq -r ".spec.host")
aws_alias() {
  AWS_ACCESS_KEY_ID=$NOOBAA_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$NOOBAA_SECRET_KEY aws --endpoint "$S3_ENDPOINT" --no-verify-ssl "$@"
}

aws_alias s3api put-bucket-notification --bucket "foo-bucket" --notification-configuration '{
  "TopicConfiguration": {
    "Id": "'$logger_connection'",
    "Events": ["s3:ObjectCreated:*"],
    "Topic": "'${logger_connection}'/connect.json"
  }
}'

aws_alias s3api put-bucket-notification --bucket "foo-bucket" --notification-configuration '{
  "TopicConfiguration": {
    "Id": "'$thumbnailer_connection'",
    "Events": ["s3:ObjectCreated:*"],
    "Topic": "'${thumbnailer_connection}'/connect.json"
  }
}'

