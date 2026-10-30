#!/bin/sh
# Idempotent Polaris setup (spec section 5.1): catalog lab_catalog, principal spark_user,
# principal role spark_role, catalog role lab_admin, and the grants. Writes the spark_user
# credentials to /secrets/spark_user.env. POSIX sh: the image has no bash and no jq, so the
# JSON answers are read with sed.
set -eu

API=http://polaris:8181
MGMT=$API/api/management/v1
OUT=/secrets/spark_user.env
ANSWER=/tmp/polaris-answer

fail() { echo "polaris-setup: $*" >&2; exit 1; }
# The answer file can hold the clientSecret.
trap 'rm -f "$ANSWER" "$OUT.new"' EXIT

: "${POLARIS_ROLE_ARN:?}" "${POLARIS_EXTERNAL_ID:?}" "${S3_BUCKET:?}" "${AWS_REGION:?}"
# Docker creates a missing ./secrets as root; `make up` creates it as the host user.
[ -w /secrets ] || fail "secrets/ is not writable by UID $(id -u): run 'sudo chown $(id -u) secrets' on the host, then make up"
case ${S3_PATH_STYLE_ACCESS:-false} in true|false) ;; *) fail "S3_PATH_STYLE_ACCESS must be true or false" ;; esac

# field NAME: prints the string value of the JSON field NAME in $ANSWER.
field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" "$ANSWER"; }

# The retry covers a restart while Polaris is still booting.
curl -fsS --retry 30 --retry-all-errors --retry-delay 2 -o "$ANSWER" -X POST "$API/api/catalog/v1/oauth/tokens" \
  --user "$POLARIS_ROOT_CLIENT_ID:$POLARIS_ROOT_CLIENT_SECRET" \
  -d grant_type=client_credentials -d scope=PRINCIPAL_ROLE:ALL || fail "no root token"
token=$(field access_token)
[ -n "$token" ] || fail "no access_token in the token answer"

# call METHOD PATH BODY: prints the HTTP code; the answer goes to $ANSWER.
call() {
  curl -sS -o "$ANSWER" -w '%{http_code}' -X "$1" \
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
    "$MGMT$2" -d "$3"
}

# create WHAT METHOD PATH BODY: HTTP 2xx = created (set for PUT), 409 = already present.
create() {
  what=$1; shift
  verb=created; [ "$1" = PUT ] && verb=set
  code=$(call "$@")
  case $code in
    2??) echo "polaris-setup: $what $verb" ;;
    409) echo "polaris-setup: $what already present" ;;
    *) fail "$what: HTTP $code: $(cat "$ANSWER")" ;;
  esac
}

location="s3://$S3_BUCKET/polaris/"
# S3-compatible storage on-premise: endpoint and path-style access (not tested on AWS).
extra=""
if [ -n "${S3_ENDPOINT:-}" ]; then
  extra=",\"endpoint\":\"$S3_ENDPOINT\",\"pathStyleAccess\":${S3_PATH_STYLE_ACCESS:-false}"
  # S3-compatible storage such as RustFS rejects the KMS resources that Polaris adds to the session policy.
  extra="$extra,\"kmsUnavailable\":true"
fi
create "catalog lab_catalog" POST /catalogs "{\"catalog\":{\"name\":\"lab_catalog\",\"type\":\"INTERNAL\",\"readOnly\":false,\"properties\":{\"default-base-location\":\"$location\"},\"storageConfigInfo\":{\"storageType\":\"S3\",\"roleArn\":\"$POLARIS_ROLE_ARN\",\"externalId\":\"$POLARIS_EXTERNAL_ID\",\"region\":\"$AWS_REGION\",\"allowedLocations\":[\"$location\"]$extra}}}"

# Polaris shows the spark_user secret only once: in the answer to the create call,
# or to a reset call.
code=$(call POST /principals '{"principal":{"name":"spark_user"}}')
case $code in
  201) echo "polaris-setup: principal spark_user created"; write=1 ;;
  409)
    # The file is kept only if it works: a token call as spark_user (nothing is printed).
    if [ -s "$OUT" ] && ( . "$OUT" && curl -fsS -o /dev/null -X POST "$API/api/catalog/v1/oauth/tokens" \
        --user "$POLARIS_SPARK_CLIENT_ID:$POLARIS_SPARK_CLIENT_SECRET" \
        -d grant_type=client_credentials -d scope=PRINCIPAL_ROLE:ALL ) >/dev/null 2>&1; then
      echo "polaris-setup: principal spark_user already present, credentials file kept"; write=0
    else
      reason="credentials file does not work, credentials reset"
      [ -s "$OUT" ] || reason="principal spark_user already present, credentials reset"
      code=$(call POST /principals/spark_user/reset '{}')
      [ "$code" = 200 ] || fail "reset spark_user: HTTP $code"
      echo "polaris-setup: $reason"; write=1
    fi ;;
  *) fail "principal spark_user: HTTP $code: $(cat "$ANSWER")" ;;
esac
if [ "$write" = 1 ]; then
  id=$(field clientId)
  secret=$(field clientSecret)
  [ -n "$id" ] && [ -n "$secret" ] || fail "no clientId or clientSecret in the answer"
  umask 077
  printf 'POLARIS_SPARK_CLIENT_ID=%s\nPOLARIS_SPARK_CLIENT_SECRET=%s\n' "$id" "$secret" >"$OUT.new"
  mv "$OUT.new" "$OUT"
  echo "polaris-setup: credentials written to secrets/spark_user.env"
  if [ "$code" = 200 ]; then
    echo "polaris-setup: credentials reset; run 'docker compose restart spark' if spark is already running"
  fi
fi

create "principal role spark_role" POST /principal-roles '{"principalRole":{"name":"spark_role"}}'
create "spark_role for spark_user" PUT /principals/spark_user/principal-roles '{"principalRole":{"name":"spark_role"}}'
create "catalog role lab_admin" POST /catalogs/lab_catalog/catalog-roles '{"catalogRole":{"name":"lab_admin"}}'
create "grant CATALOG_MANAGE_CONTENT" PUT /catalogs/lab_catalog/catalog-roles/lab_admin/grants '{"grant":{"type":"catalog","privilege":"CATALOG_MANAGE_CONTENT"}}'
create "lab_admin for spark_role" PUT /principal-roles/spark_role/catalog-roles/lab_catalog '{"catalogRole":{"name":"lab_admin"}}'

echo "polaris-setup: done"
