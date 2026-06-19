#!/usr/bin/env bash

function create_account() {
  local account

  account=$1

  POD=$(oc get pods -n openshift-storage -l=noobaa-operator --no-headers -o=custom-columns=NAME:.metadata.name)
  oc exec -n openshift-storage $POD -- /usr/local/bin/noobaa-operator account create ${account}
  oc wait --for=create -n openshift-storage "secret/noobaa-account-$account" --timeout=30s
}

function copy_account_secret_to_namespace() {
  local account namespace
  account=$1
  namespace=$2
  
  # Copy the account secret to the namespace
  ARN=$(oc -n openshift-storage get secret "noobaa-account-$account" --template='{{index .data "ARN"}}' | base64 --decode )
  AWS_ACCESS_KEY_ID=$(oc -n openshift-storage get secret "noobaa-account-$account" --template='{{index .data "AWS_ACCESS_KEY_ID"}}' | base64 --decode )
  AWS_SECRET_ACCESS_KEY=$(oc -n openshift-storage get secret "noobaa-account-$account" --template='{{index .data "AWS_SECRET_ACCESS_KEY"}}' | base64 --decode )

  oc create secret --namespace "${namespace}" generic "noobaa-account-$account" \
      --from-literal=ARN="$ARN" \
      --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
      --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
}

function grant_obc_access_to_account() {
  local namespace obc bucket_name
  namespace=$1
  obc=$2
  account=$3

  bucket_name=$(oc get obc "$obc" -o json | jq -r '.spec.bucketName')

  account_arn=$(oc get secret -n openshift-storage "noobaa-account-$account" -o json | jq -r '.data.ARN' | base64 --decode)

  NOOBAA_ACCESS_KEY=$(oc extract secret/"$obc" -n "$namespace" --keys=AWS_ACCESS_KEY_ID --to=- 2>/dev/null); \
  NOOBAA_SECRET_KEY=$(oc extract secret/"$obc" -n "$namespace" --keys=AWS_SECRET_ACCESS_KEY --to=- 2>/dev/null); \
  S3_ENDPOINT=https://$(oc get route s3 -n openshift-storage -o json | jq -r ".spec.host")
  aws_alias() {
    AWS_ACCESS_KEY_ID=$NOOBAA_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$NOOBAA_SECRET_KEY aws --endpoint "$S3_ENDPOINT" --no-verify-ssl "$@"
  }

  tmp=$(mktemp -d)

  cat > $tmp/policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Allow${account}AccessTo$bucket_name",
      "Effect": "Allow",
      "Principal": {
        "AWS":"$account_arn"
      },
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": [
        "arn:aws:s3:::$bucket_name",
        "arn:aws:s3:::$bucket_name/*"
      ]
    }
  ]
}
EOF

  aws_alias s3api put-bucket-policy --bucket "${bucket_name}" --policy "file://$tmp/policy.json"
}

create_account foobar-ns-account
copy_account_secret_to_namespace foobar-ns-account foobar
grant_obc_access_to_account foobar foo-bucket foobar-ns-account
grant_obc_access_to_account foobar foo-bucket-resized foobar-ns-account

